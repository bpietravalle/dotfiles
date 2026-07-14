#!/usr/bin/env zsh
# Regression tests for the orphan pruners (second surface).
#   zsh .zsh/git-prune-orphans.test.zsh
#
# git-prune-gone was fixed first (see git-prune-gone.test.zsh). It was not the whole
# defect — the SAME "absence of a signal = permission to destroy" reasoning survived in
# _git_prune_local_orphans and _git_prune_remote_orphans, reachable from the everyday
# `git-sync`, with no preview and no confirmation. These lock it out of both.
#
# Every test builds a THROWAWAY repo (a bare "origin" + a clone) under a temp dir and
# drives the real functions. Nothing here touches a real repo.
#
# The locks, in order of how badly they hurt when broken:
#
#   1. A NEVER-PUSHED branch with unmerged commits, older than the grace window, is
#      KEPT. The old `deletable-old` verdict force-deleted it after 2h — and because it
#      has no upstream it was never `[gone]`, so git-prune-gone could not even SEE it.
#      `git-sync` was strictly MORE dangerous than the tool this ticket was filed for.
#   2. A branch whose PR was CLOSED WITHOUT MERGING is KEPT. The old verdict read any
#      non-OPEN PR as "captured" — i.e. it read the strongest available signal that work
#      was abandoned unlanded as permission to force-delete it.
#   3. A LOCKED worktree is never removed and never unlocked. The old code ran
#      `git worktree unlock` and then `git worktree remove --force` — defeating the one
#      mechanism an agent has to say "this is mine" (a prior incident deleted 22 worktrees).
#   4. A REMOTE branch that is pushed, PR-less and old is KEPT. The old remote gate
#      deleted exactly that — the canonical shape of a rescue branch, on the copy of
#      last resort.
#   5. Fail closed, and THE LIST SHOWN IS THE LIST DELETED.

emulate -L zsh
setopt no_unset pipefail

SELF_DIR="${0:A:h}"
source "$SELF_DIR/git.zsh"

typeset -g PASS=0 FAIL=0
# `return 0` is load-bearing — see the note in git-prune-gone.test.zsh.
ok()  { print "ok   $1"; (( PASS++ )); return 0 }
nok() { print "FAIL $1\n       $2"; (( FAIL++ )); return 0 }
assert()     { [[ "$2" == "$3" ]] && ok "$1" || nok "$1" "want '$3' got '$2'" }
assert_has() { [[ "$2" == *"$3"* ]] && ok "$1" || nok "$1" "expected to contain '$3'
       got: $2" }
assert_not() { [[ "$2" != *"$3"* ]] && ok "$1" || nok "$1" "must NOT contain '$3'
       got: $2" }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; [[ -n ${STUB:-} ]] && rm -rf "$STUB"' EXIT

new_repo() {
  local name="$1" root="$TMP/$1"
  mkdir -p "$root"
  git init -q --bare "$root/origin.git"
  git clone -q "$root/origin.git" "$root/work" 2>/dev/null
  git -C "$root/work" config user.email t@t; git -C "$root/work" config user.name t
  git -C "$root/work" commit -q --allow-empty -m init
  git -C "$root/work" branch -M master
  git -C "$root/work" push -q -u origin master
  git -C "$root/work" remote set-head origin -a >/dev/null 2>&1
  print "$root/work"
}

branches()        { git -C "$1" for-each-ref --format '%(refname:short)' refs/heads | LC_ALL=C sort | tr '\n' ' ' }
remote_branches() { git -C "$1" ls-remote --heads origin | awk '{sub("refs/heads/","",$2); print $2}' | LC_ALL=C sort | tr '\n' ' ' }

# Backdate a branch tip so it is past GIT_PRUNE_MIN_AGE without waiting 2h.
age_branch() {
  local repo="$1" branch="$2" secs="${3:-99999}"
  local when
  when=$(( $(date +%s) - secs ))
  git -C "$repo" checkout -q "$branch"
  GIT_COMMITTER_DATE="$when" GIT_AUTHOR_DATE="$when" \
    git -C "$repo" commit -q --amend --no-edit --allow-empty --date="$when"
  git -C "$repo" checkout -q master
}

# gh is stubbed; the stub dir goes FIRST on PATH. A directory that merely LACKS gh is
# not enough — the real, network-facing gh is still further down $PATH.
STUB="$(mktemp -d)"
GH_PATH="$STUB/bin:$PATH"
mkdir -p "$STUB/bin"

# mk_gh <auth_rc> <merged_pr_stdout> <pr_rc> [<open_pr_head>]
#   merged_pr_stdout — what `gh pr list --state merged` yields (a PR number, or empty)
#   open_pr_head     — what `gh pr list --state open` yields (a branch name, or empty);
#                      this is what _git_remote_orphans consults.
mk_gh() {
  cat > "$STUB/bin/gh" <<STUBEOF
#!/bin/sh
case "\$1" in
  auth) exit $1 ;;
  pr)
    for a in "\$@"; do
      if [ "\$a" = "open" ]; then printf '%s' '${4:-}'; exit 0; fi
    done
    printf '%s' '$2'; exit $3 ;;
esac
exit 0
STUBEOF
  chmod +x "$STUB/bin/gh"
}
gh_absent() { mk_gh 1 ""   0 }      # not installed / not authed -> cannot prove anything
gh_merged() { mk_gh 0 "42" 0 }      # origin: a MERGED PR exists for the branch
gh_no_pr()  { mk_gh 0 ""   0 }      # origin: no merged PR
gh_error()  { mk_gh 0 ""   1 }      # gh itself failed -> no proof

gh_no_pr   # default for every test not specifically about gh

# ── 1. THE INCIDENT, LOCAL: never-pushed, unmerged, PAST the grace window ──────
# The old `deletable-old` verdict: "no PR + last commit older than 2h" -> git branch -D.
# Age is not proof. This branch has irreplaceable commits and no copy anywhere.
R=$(new_repo old_unlanded)
git -C "$R" checkout -q -b rescue-work
git -C "$R" commit -q --allow-empty -m "irreplaceable work"
git -C "$R" checkout -q master
age_branch "$R" rescue-work                       # 27h old: WAY past the 2h grace
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
assert_has "1a old, never-pushed, unlanded branch is KEPT"  "$OUT" "unlanded work"
assert_not "1b it is never deleted"                         "$OUT" "deleted  rescue-work"
assert     "1c the commits survive"  "$(branches "$R")" "master rescue-work "

# ── 2. A CLOSED (unmerged) PR is not "captured" ───────────────────────────────
# The old verdict: any PR state that is not OPEN -> deletable-captured -> -D.
# A closed-unmerged PR is the strongest signal work was abandoned WITHOUT landing.
R=$(new_repo closed_pr)
git -C "$R" checkout -q -b abandoned
git -C "$R" commit -q --allow-empty -m "work someone closed the PR on"
git -C "$R" push -q -u origin abandoned
git -C "$R" push -q origin --delete abandoned
git -C "$R" checkout -q master
gh_no_pr                                          # no MERGED PR (the PR was closed)
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
assert_has "2a closed-unmerged PR branch is KEPT" "$OUT" "unlanded work"
assert     "2b it survives"  "$(branches "$R")" "abandoned master "

# ── 3. Proof works: a genuinely merged branch IS deleted ──────────────────────
R=$(new_repo merged_local)
git -C "$R" checkout -q -b feature
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff feature -m "merge feature"
git -C "$R" push -q origin master
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
assert_has "3a a proven-landed branch is deleted" "$OUT" "deleted  feature"
assert     "3b only master remains"  "$(branches "$R")" "master "

# 3c. Squash merge: only a MERGED PR on origin proves it.
R=$(new_repo squash_local)
git -C "$R" checkout -q -b squashed
git -C "$R" commit -q --allow-empty -m work
git -C "$R" push -q -u origin squashed
git -C "$R" push -q origin --delete squashed
git -C "$R" checkout -q master
gh_merged
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
assert_has "3c squash-merged branch (merged PR) is deleted" "$OUT" "deleted  squashed"
gh_no_pr

# ── 4. A LOCKED worktree is never unlocked and never removed ──────────────────
# The old code: `git worktree unlock` && `git worktree remove --force`. A lock is an
# agent saying "this is mine". Note the branch here is genuinely LANDED — so proof is
# satisfied and only the lock stands between the agent's directory and deletion.
R=$(new_repo locked_wt)
git -C "$R" checkout -q -b agent-branch
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff agent-branch -m merge      # LANDED: a delete candidate
git -C "$R" push -q origin master
git -C "$R" worktree add -q "$TMP/wt-locked" agent-branch
git -C "$R" worktree lock "$TMP/wt-locked"
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
assert_has "4a a locked worktree is reported, not removed"  "$OUT" "live worktree"
assert     "4b the worktree directory still exists"         "$([[ -d $TMP/wt-locked ]] && echo yes)" "yes"
assert     "4c the branch survives"  "$(branches "$R")" "agent-branch master "
assert     "4d it is still LOCKED (never unlocked)" \
  "$(git -C "$R" worktree list --porcelain | grep -c '^locked')" "1"
assert_not "4e no unlock anywhere in the file" \
  "$(typeset -f _git_prune_local_orphans _git_merge_pr_clean_scoped)" "worktree unlock"

# 4f. A DIRTY (unlocked) worktree on a landed branch is also protected — the old code
# used `remove --force` precisely to blow past git's refusal to remove a dirty tree.
R=$(new_repo dirty_wt)
git -C "$R" checkout -q -b dirty-branch
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff dirty-branch -m merge
git -C "$R" push -q origin master
git -C "$R" worktree add -q "$TMP/wt-dirty" dirty-branch
echo "an agent's uncommitted work" > "$TMP/wt-dirty/in-flight.txt"
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
assert     "4f dirty worktree keeps its uncommitted file" \
  "$(cat "$TMP/wt-dirty/in-flight.txt" 2>/dev/null)" "an agent's uncommitted work"
assert     "4g and its branch"  "$(branches "$R")" "dirty-branch master "

# ── 5. THE REMOTE: pushed, PR-less, old — the shape of a rescue branch ────────
# The old remote gate deleted origin/<b> on "no open PR + 6h old". That is the exact
# description of the 20 fork-bomb rescue branches, on the copy of last resort.
R=$(new_repo remote_rescue)
git -C "$R" checkout -q -b rescue-42
git -C "$R" commit -q --allow-empty -m "the only copy of this work"
git -C "$R" push -q -u origin rescue-42
git -C "$R" checkout -q master
gh_no_pr                                     # no open PR, and no merged PR
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_remote_orphans 0 2>&1)
assert_has "5a unlanded remote branch is HELD"    "$OUT" "Held back"
assert_not "5b it is not deleted from origin"     "$OUT" "Deleting origin/rescue-42"
assert     "5c it still exists on origin"  "$(remote_branches "$R")" "master rescue-42 "

# 5d. A genuinely landed remote branch IS deleted (the feature still works).
R=$(new_repo remote_landed)
git -C "$R" checkout -q -b done-work
git -C "$R" commit -q --allow-empty -m work
git -C "$R" push -q -u origin done-work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff done-work -m merge
git -C "$R" push -q origin master
age_branch "$R" done-work 99999              # past the 6h remote grace...
git -C "$R" push -q -f origin done-work      # ...and re-push so origin carries it
git -C "$R" checkout -q master
git -C "$R" merge -q done-work -m merge2 2>/dev/null || true
git -C "$R" push -q origin master
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_remote_orphans 0 2>&1)
assert_has "5d a proven-landed remote branch is deleted" "$OUT" "Deleting origin/done-work"
assert     "5e origin is cleaned"  "$(remote_branches "$R")" "master "

# ── 6. FAIL CLOSED ───────────────────────────────────────────────────────────
# 6a/b. gh unavailable -> squash merges are unprovable -> keep, never delete.
R=$(new_repo ghgone)
git -C "$R" checkout -q -b unprovable
git -C "$R" commit -q --allow-empty -m work
git -C "$R" push -q -u origin unprovable
git -C "$R" push -q origin --delete unprovable
git -C "$R" checkout -q master
gh_absent
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
assert_has "6a gh unavailable KEEPS the branch" "$OUT" "fail closed"
assert     "6b it survives"  "$(branches "$R")" "master unprovable "

# 6c/d. gh errors -> no proof -> keep.
gh_error
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
assert_has "6c gh error KEEPS the branch" "$OUT" "fail closed"
assert     "6d it survives"  "$(branches "$R")" "master unprovable "
gh_no_pr

# 6e/f/g. fetch fails -> origin cannot be seen -> delete NOTHING, non-zero exit.
# The old code ran `git fetch --prune ... || true` and pruned against a stale view.
R=$(new_repo fetchfail)
git -C "$R" checkout -q -b feature2
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff feature2 -m merge     # genuinely landed...
git -C "$R" push -q origin master
git -C "$R" remote set-url origin "$TMP/nope.git"  # ...but origin is unreachable
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1); RC=$?
assert     "6e fetch failure exits non-zero"   "$RC" "1"
assert_has "6f it says why"                    "$OUT" "refusing to delete anything"
assert     "6g even a LANDED branch survives"  "$(branches "$R")" "feature2 master "

# ── 7. THE LIST SHOWN IS THE LIST DELETED ────────────────────────────────────
# The invariant behind all four of 2026-07-13's destructive-tooling bugs. The old
# _git_prune_local_orphans showed only what it PROTECTED, and narrated destruction as
# it happened — a receipt, not a preview.
R=$(new_repo shown_is_deleted)
for i in 1 2 3; do
  git -C "$R" checkout -q -b "landed-$i"
  git -C "$R" commit -q --allow-empty -m "w$i"
  git -C "$R" checkout -q master
  git -C "$R" merge -q --no-ff "landed-$i" -m "merge $i"
done
git -C "$R" checkout -q -b unlanded-keep
git -C "$R" commit -q --allow-empty -m "not merged"
git -C "$R" checkout -q master
git -C "$R" push -q origin master
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --yes 2>&1)
SHOWN=$(print -r -- "$OUT" | sed -n '/Will DELETE/,/^  deleted/p' \
        | grep -oE 'landed-[0-9]+|unlanded-keep' | sort -u | tr '\n' ' ')
GONE=$(print -r -- "$OUT" | grep '^  deleted' | awk '{print $2}' | sort | tr '\n' ' ')
assert "7a shown == deleted"                 "$SHOWN" "$GONE"
assert "7b the unlanded branch is untouched" "$(branches "$R")" "master unlanded-keep "

# ── 8. --dry-run destroys nothing; --force cannot force an unlanded branch out ──
R=$(new_repo dryrun)
git -C "$R" checkout -q -b feature4
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff feature4 -m merge
git -C "$R" push -q origin master
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --dry-run 2>&1)
assert_has "8a dry-run names the branch" "$OUT" "feature4"
assert     "8b it survives"  "$(branches "$R")" "feature4 master "

# 8c. --force used to promote an OPEN-PR / within-grace branch to deletable. Under
# landed-proof there is nothing for it to override: no flag turns "cannot prove this
# landed" into "destroy it".
R=$(new_repo forced)
git -C "$R" checkout -q -b wip-work
git -C "$R" commit -q --allow-empty -m "unlanded WIP"
git -C "$R" checkout -q master
OUT=$(cd "$R" && PATH="$GH_PATH" _git_prune_local_orphans --force --yes 2>&1)
assert_has "8c --force still KEEPS an unlanded branch" "$OUT" "unlanded work"
assert     "8d it survives --force"  "$(branches "$R")" "master wip-work "

print "\n$PASS passed, $FAIL failed"
(( FAIL == 0 ))
