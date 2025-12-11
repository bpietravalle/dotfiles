# Quick Reference

## Keyboard Shortcuts

### Tmux (Prefix: C-a)

```
Panes                          Windows
─────────────────────────────────────────────────
C-a -     Split horizontal     C-a c     New window
C-a \     Split vertical       C-a l     Last window
C-a h/j/k/l  Navigate          C-a 0-9   Go to window
C-a H/J/K/L  Resize            C-a ,     Rename window
M-h/j/k/l    Navigate (no pfx) C-a w     List windows

Sessions                       Misc
─────────────────────────────────────────────────
C-a (     Previous session     C-a r     Reload config
C-a )     Next session         C-a C-s   Sync panes
C-a d     Detach               C-a J     Join pane
C-a $     Rename session       C-a P     Log pane
C-a B     Return to monitor
```

### Vim

```
Leader: \

File Operations               ALE/LSP
─────────────────────────────────────────────────
\w        Save                 \gd       Go to definition
\ev       Edit vimrc           \gr       Find references
\cv       Reload vimrc         \gh       Hover info
\nt       NERDTree CWD         \ca       Code action
C-n       Toggle NERDTree      \rn       Rename symbol
C-p       Fuzzy find           \en/\ep   Next/prev error

Formatting                    Git (Fugitive)
─────────────────────────────────────────────────
\pr       Prettier             \gs       Git status
\af       Autoformat           \gd       Git diff
C-f       JS/HTML/CSS beautify \gb       Git blame

Navigation                    Buffers
─────────────────────────────────────────────────
\lo       Open location list   [b        Previous buffer
\lc       Close location list  ]b        Next buffer
\cl       Close quickfix       [B        First buffer
                               ]B        Last buffer
```

---

## Common Commands

### Shell

```bash
# Reload zsh
reload                    # Or: source ~/.zshrc

# Quick navigation
ms <project>              # Start tmuxinator project
tat <session>             # Attach to tmux session
tls                       # List tmux sessions
tks <session>             # Kill tmux session

# Docker
dk                        # docker
dkc                       # docker compose
docker-clean              # Prune containers/images/volumes
dkspf                     # System prune -f

# Git
gs                        # git status
ga                        # git add
gb                        # git branch
gc                        # git commit
gd                        # git diff

# Terraform
tfw                       # terraform workspace
tfa                       # terraform apply
```

### Git Aliases

```bash
git l                     # Pretty log
git ll                    # Log with numstat
git ls                    # Log with file status
git lg                    # Graph log
git lt                    # Last 24h commits
git ds                    # Diff staged
git dc                    # Diff HEAD
git uncommit              # Soft reset HEAD^
git incoming              # Show incoming changes
git outgoing              # Show outgoing commits
git replace "old" "new"   # Global find/replace
```

---

## Claude Monitor

Monitor multiple Claude Code instances across tmux sessions.

### Commands

```bash
# Status & Control
claude-util monitor status         # Show monitor status
claude-util monitor list           # List all Claude instances
claude-util monitor start          # Start background daemon
claude-util monitor stop           # Stop daemon + kill orphans
claude-util monitor restart        # Restart daemon

# Live Dashboards
claude-util monitor -f             # Foreground mode (simple)
claude-util monitor -fv            # Verbose dashboard (output preview)
claude-util monitor attach         # Same as -f

# Navigation
claude-util monitor goto <session> # Jump to session's Claude pane
claude-util monitor back           # Switch back to dashboard (C-a B)

# Configuration
claude-util monitor verbosity [lvl] # silent|minimal|verbose
claude-util monitor debug [on|off]  # Toggle debug logging
claude-util monitor logs [n]        # Show last n log lines (default: 50)

# Recovery
claude-util unfreeze [pane]        # Kill monitor + reset frozen pane TTY
```

### Verbose Dashboard Keys

```
1-9       Jump to numbered instance (dashboard keeps running)
r         Refresh display (fix visual glitches)
q         Quit dashboard
C-a B     Switch back to dashboard (tmux binding)
```

### State Icons

```
●  active     Claude is working (output changing)
⏳ idle       No output change for 30s (needs attention)
🔐 permission Likely a permission prompt
?  question   Likely asking a question
```

### Recovery: Frozen Pane

If the monitor leaves a pane frozen (no keyboard response):

```bash
# From another tmux session/pane:

# Option 1: Quick recovery (kills monitor + resets target pane)
claude-util unfreeze dotfiles:0.1

# Option 2: Just kill the monitor
claude-util unfreeze

# Option 3: Manual steps
pgrep -fl claude-monitor-daemon    # Find PIDs
kill <pid>                          # Kill monitor
tmux send-keys -t dotfiles:0.1 "stty sane; clear" Enter
```

**Debug logging**: Off by default. Enable with `claude-util monitor debug on`

**Logs**: `~/.claude/monitor/daemon.log` (only when debug enabled)

---

## Process Management

Find and kill runaway processes. Kill uses tree-killing (children first, then parent).

```bash
# List
claude-util procs list                    # Top 5
claude-util procs list -t dev --oldest    # Dev processes by age
claude-util procs list --largest --all    # All by memory

# Kill (kills process trees)
claude-util procs kill 12345              # Specific PID + children
claude-util procs kill -t dev --oldest    # Oldest dev trees
claude-util procs kill --force            # Use SIGKILL (-9)
claude-util procs clean                   # Interactive cleanup
```

**Types** (`-t`/`--type`):
- 🔒 `claude`, `daemon`, `mcp`, `lsp` = protected
- ✅ `test`, `agent` = safe to kill
- ⚠️ `dev`, `other` = caution

**Flags**: `--oldest`, `--largest`, `--count N`, `--force/-9`, `--all`

---

## Utility Functions

```bash
extract <file>            # Extract any archive format
trash <files>             # Safe delete to ~/.Trash
zsh_recompile             # Recompile zsh for speed
get_github_url <file>     # Copy GitHub URL to clipboard
gitFindReplace old new    # Git-aware find/replace
```

---

## File Locations

```
Configuration               Description
─────────────────────────────────────────────────
~/.zshrc                   Zsh entry point
~/.zsh/                    Modular zsh config
~/.vimrc                   Vim config
~/.tmux.conf               Tmux config
~/.tmuxinator/             Project layouts
~/.gitconfig               Git config

Scripts                     Purpose
─────────────────────────────────────────────────
~/bin/                     User scripts (symlinked)
~/dev/dotfiles/bin/        Script sources
~/dev/dotfiles/scripts/    Installation scripts
```

---

## Troubleshooting

### Vim Slow?

```vim
:profile start profile.log
:profile file *
:profile func *
" ... do slow action ...
:profile pause
:noautocmd qall!
```

### Git Corrupted Objects?

```bash
fixGitObjectsCorruptedErrors
```

### Swap Files?

```bash
removeVimBuffers
```

### Docker Cleanup?

```bash
docker-clean
```
