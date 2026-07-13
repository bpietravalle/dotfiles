#!/usr/bin/env zsh
# Regression tests for git-prune-gone (RVT-2886).
#   zsh .zsh/git-prune-gone.test.zsh
#
# Every test builds a THROWAWAY repo (a bare "origin" + a clone) under a temp dir and
# drives the real function. Nothing here touches a real repo, and the function is never
# run anywhere but inside these sandboxes.
#
# The locks, in order of how badly they hurt when broken:
#
#   1. An UNLANDED branch whose remote ref is [gone] is KEPT.  <- the 2026-07-13 incident:
#      [gone] means "the remote ref is missing", never "the work landed".
#   2. Every fail-closed path KEEPS: fetch failure, unresolvable origin/HEAD, gh absent,
#      gh erroring. An error is not proof, and the error case IS the dangerous population
#      (RVT-2881 read `git log @{u}..` exiting 128 with empty stdout as "safe to delete").
#   3. THE LIST SHOWN IS THE LIST DELETED — asserted by diffing the two.
#   4. There is no worktree skip-list, and none is needed: git itself refuses to delete a
#      branch checked out in a worktree.

emulate -L zsh
setopt no_unset pipefail

SELF_DIR="${0:A:h}"
source "$SELF_DIR/git.zsh"

typeset -g PASS=0 FAIL=0
# `return 0` is load-bearing: these run as `[[ ... ]] && ok || nok`, and a bare
# `(( PASS++ ))` returns exit 1 when PASS is 0 (post-increment yields the OLD value), so
# the first passing assertion would fire `nok` as well. That bug reported test 1a — the
# most important assertion in this file — as FAILING while the function was correct.
ok()  { print "ok   $1"; (( PASS++ )); return 0 }
nok() { print "FAIL $1\n       $2"; (( FAIL++ )); return 0 }
assert()     { [[ "$2" == "$3" ]] && ok "$1" || nok "$1" "want '$3' got '$2'" }
assert_has() { [[ "$2" == *"$3"* ]] && ok "$1" || nok "$1" "expected to contain '$3'
       got: $2" }
assert_not() { [[ "$2" != *"$3"* ]] && ok "$1" || nok "$1" "must NOT contain '$3'
       got: $2" }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; [[ -n ${STUB:-} ]] && rm -rf "$STUB"' EXIT

# A repo with an origin. Returns the clone's path on stdout.
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

branches() { git -C "$1" for-each-ref --format '%(refname:short)' refs/heads | LC_ALL=C sort | tr '\n' ' ' }

# gh is consulted only for the squash-merge proof, so every test must control what it
# says. It is stubbed and the stub dir goes FIRST on PATH.
#
# It is NOT enough to prepend a directory that merely lacks gh — the real gh is still
# further down $PATH. (The first version of this file did exactly that; the tests then
# invoked the real, network-facing gh against a sandbox repo, and only the fail-closed
# design stopped that from mattering.) So the "absent" case is a stub whose `auth status`
# FAILS, which is the same gh_ok=0 branch as gh not being installed.
STUB="$(mktemp -d)"
GH_PATH="$STUB/bin:$PATH"
mkdir -p "$STUB/bin"

# mk_gh <auth_rc> <pr_stdout> <pr_rc>
mk_gh() {
  cat > "$STUB/bin/gh" <<STUBEOF
#!/bin/sh
case "\$1" in
  auth) exit $1 ;;
  pr)   printf '%s' '$2'; exit $3 ;;
esac
exit 0
STUBEOF
  chmod +x "$STUB/bin/gh"
}
gh_absent()  { mk_gh 1 ""   0 }   # not installed / not authenticated -> cannot prove
gh_merged()  { mk_gh 0 "42" 0 }   # origin: PR #42, merged
gh_no_pr()   { mk_gh 0 ""   0 }   # origin: no merged PR for this branch
gh_error()   { mk_gh 0 ""   1 }   # gh itself failed -> no proof

# Default for every test that is not specifically about gh: origin has no merged PR.
# This MUST be written before the first test, or $STUB/bin has no gh at all and the
# real one is found further down PATH.
gh_no_pr

# ── 1. THE INCIDENT: unlanded work whose remote ref was deleted ────────────────
# Branch was pushed, then its remote head was deleted WITHOUT merging. `%(upstream:track)`
# now reads [gone] — identical to a squash-merged branch. The old code force-deleted it.
R=$(new_repo unlanded)
git -C "$R" checkout -q -b rescue-work
git -C "$R" commit -q --allow-empty -m "irreplaceable work"
git -C "$R" push -q -u origin rescue-work
git -C "$R" push -q origin --delete rescue-work         # remote ref gone; NOTHING merged
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert_has "1a [gone]-but-unlanded branch is KEPT"        "$OUT" "KEPT"
assert_not "1b it is not in the delete list"              "$OUT" "deleted  rescue-work"
assert     "1c the branch still exists"                   "$(branches "$R")" "master rescue-work "

# ── 2. An ordinary merge IS proof — that branch is deleted ─────────────────────
R=$(new_repo merged)
git -C "$R" checkout -q -b feature
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff feature -m "merge feature"
git -C "$R" push -q origin master
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert_has "2a merged branch is deleted"      "$OUT" "deleted  feature"
assert     "2b only master remains"           "$(branches "$R")" "master "

# ── 3. Never-pushed branch WITH COMMITS is KEPT (no upstream = no proof) ──────
# The population RVT-2881 destroyed by reading `git log @{u}..`'s exit-128 as "safe".
R=$(new_repo neverpushed)
git -C "$R" checkout -q -b local-only
git -C "$R" commit -q --allow-empty -m "never pushed anywhere"
git -C "$R" checkout -q master
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert_has "3a never-pushed branch with commits is KEPT" "$OUT" "KEPT"
assert     "3b it survives"                              "$(branches "$R")" "local-only master "

# 3c. A branch with NO commits of its own (same tip as origin/master) is an ancestor,
# so it IS deleted — deliberately. It carries no work; there is nothing to lose but the
# name. Pinned so the behaviour is a decision on the record, not an accident.
R=$(new_repo emptybranch)
git -C "$R" branch no-commits-yet
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert "3c a zero-commit branch is pruned (nothing to lose)" "$(branches "$R")" "master "

# ── 4. Squash merge: only a MERGED PR on origin proves it ─────────────────────
# Same [gone] state as test 1. The ONLY difference is that origin reports a merged PR.
R=$(new_repo squashed)
git -C "$R" checkout -q -b squashed-feature
git -C "$R" commit -q --allow-empty -m work
git -C "$R" push -q -u origin squashed-feature
git -C "$R" push -q origin --delete squashed-feature
git -C "$R" checkout -q master

gh_merged                                             # origin: PR #42, merged
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert_has "4a squash-merged branch (merged PR) is deleted" "$OUT" "deleted  squashed-feature"

R=$(new_repo squashed_nopr)
git -C "$R" checkout -q -b no-pr-feature
git -C "$R" commit -q --allow-empty -m work
git -C "$R" push -q -u origin no-pr-feature
git -C "$R" push -q origin --delete no-pr-feature
git -C "$R" checkout -q master
gh_no_pr                                              # origin: no merged PR
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert_has "4b [gone] with NO merged PR is KEPT" "$OUT" "KEPT"
assert     "4c it survives"                      "$(branches "$R")" "master no-pr-feature "

# ── 5. FAIL CLOSED: gh errors → keep, never delete ────────────────────────────
R=$(new_repo gherror)
git -C "$R" checkout -q -b maybe-merged
git -C "$R" commit -q --allow-empty -m work
git -C "$R" push -q -u origin maybe-merged
git -C "$R" push -q origin --delete maybe-merged
git -C "$R" checkout -q master
gh_error                                              # gh itself fails
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert_has "5a gh error KEEPS the branch (fail closed)" "$OUT" "fail closed"
assert     "5b it survives"                             "$(branches "$R")" "master maybe-merged "

# 5c. FAIL CLOSED: gh not installed / not authenticated -> cannot prove a squash merge.
R=$(new_repo ghabsent)
git -C "$R" checkout -q -b unprovable
git -C "$R" commit -q --allow-empty -m work
git -C "$R" push -q -u origin unprovable
git -C "$R" push -q origin --delete unprovable
git -C "$R" checkout -q master
gh_absent
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert_has "5c gh unavailable KEEPS the branch (fail closed)" "$OUT" "gh unavailable"
assert     "5d it survives"                                   "$(branches "$R")" "master unprovable "

gh_no_pr   # restore the default for the remaining tests

# ── 6. FAIL CLOSED: fetch fails → delete NOTHING, non-zero exit ───────────────
R=$(new_repo fetchfail)
git -C "$R" checkout -q -b feature2
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff feature2 -m merge          # genuinely landed...
git -C "$R" push -q origin master
git -C "$R" remote set-url origin "$TMP/does-not-exist.git"   # ...but origin is unreachable
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1); RC=$?
assert     "6a fetch failure exits non-zero"      "$RC" "1"
assert_has "6b it says why"                       "$OUT" "refusing to delete anything"
assert     "6c even a LANDED branch survives"     "$(branches "$R")" "feature2 master "

# ── 7. FAIL CLOSED: origin/HEAD unresolvable → delete NOTHING ─────────────────
R=$(new_repo nohead)
git -C "$R" checkout -q -b feature3
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff feature3 -m merge
git -C "$R" push -q origin master
# followRemoteHEAD=never, or the function's own `git fetch` silently RE-CREATES
# origin/HEAD (git >= 2.47) and this fail-closed path is never reached — the first
# version of this test passed for that reason while asserting nothing.
git -C "$R" config remote.origin.followRemoteHEAD never
git -C "$R" symbolic-ref -d refs/remotes/origin/HEAD     # cannot name the default branch
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1); RC=$?
assert     "7a unresolvable origin/HEAD exits non-zero" "$RC" "1"
assert_has "7b it says why"                             "$OUT" "cannot resolve origin's default branch"
assert     "7c the landed branch still survives"        "$(branches "$R")" "feature3 master "

# ── 8. --dry-run shows the list and deletes nothing ───────────────────────────
R=$(new_repo dryrun)
git -C "$R" checkout -q -b feature4
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff feature4 -m merge
git -C "$R" push -q origin master
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --dry-run 2>&1)
assert_has "8a dry-run names the branch"      "$OUT" "feature4"
assert_has "8b dry-run deletes nothing"       "$OUT" "nothing deleted"
assert     "8c the branch survives"           "$(branches "$R")" "feature4 master "

# ── 9. THE LIST SHOWN IS THE LIST DELETED ────────────────────────────────────
# The invariant behind all four of today's destructive-tooling bugs. Diff the names in
# the "Will DELETE" preview against the names actually reported deleted.
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
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
SHOWN=$(print -r -- "$OUT" | sed -n '/Will DELETE/,/^  deleted\|^  FAILED/p' \
        | grep -oE 'landed-[0-9]+|unlanded-keep' | sort -u | tr '\n' ' ')
GONE=$(print -r -- "$OUT" | grep '^  deleted' | awk '{print $2}' | sort | tr '\n' ' ')
assert "9a shown == deleted"                  "$SHOWN" "$GONE"
assert "9b the unlanded branch is untouched"  "$(branches "$R")" "master unlanded-keep "

# ── 10. No skip-list, and none needed: git protects worktree branches itself ──
R=$(new_repo worktree)
git -C "$R" checkout -q -b wt-feature
git -C "$R" commit -q --allow-empty -m work
git -C "$R" checkout -q master
git -C "$R" merge -q --no-ff wt-feature -m merge      # LANDED — so it is a delete candidate
git -C "$R" push -q origin master
git -C "$R" worktree add -q "$TMP/worktree/live" wt-feature   # ...but it is checked out
OUT=$(cd "$R" && PATH="$GH_PATH" git-prune-gone --yes 2>&1)
assert_has "10a git refuses to delete a checked-out branch" "$OUT" "FAILED   wt-feature"
assert     "10b the branch survives without any skip-list"  "$(branches "$R")" "master wt-feature "
assert_not "10c the function has no skip-list"              "$(typeset -f git-prune-gone)" "worktree list"

print "\n$PASS passed, $FAIL failed"
(( FAIL == 0 ))
