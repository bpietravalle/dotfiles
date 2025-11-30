# Configuration Guide

## Zsh Configuration

### Module Load Order

The `.zshrc` sources modules from `.zsh/` in this order:

1. `utils.zsh` - Core utilities
2. `colors.zsh` - Terminal colors
3. `setopt.zsh` - Zsh options
4. `exports.zsh` - Environment variables
5. `docker.zsh` - Docker functions
6. `prompt.zsh` - Shell prompt
7. `completion.zsh` - Tab completion
8. `aliases.zsh` - Aliases
9. `bindkeys.zsh` - Key bindings
10. `functions.zsh` - Utility functions
11. `history.zsh` - History settings
12. `py.zsh` - Python config
13. `zsh_hooks.zsh` - Hooks
14. `git.zsh` - Git functions
15. `ssh.zsh` - SSH config
16. `claude.zsh` - Claude Code utilities
17. `zsh-nvm.plugin.zsh` - Node Version Manager
18. `timemachine.zsh` - Time Machine

### Runtime Integrations

- NVM (Node Version Manager)
- rbenv (Ruby Version Manager)
- tmuxinator
- Google Cloud SDK
- Docker CLI completions
- pnpm

---

## Vim Configuration

### Plugin Manager

Uses Vundle. Install with:

```bash
git clone git@github.com:VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
vim +PluginInstall +qall
```

### Active Plugins

| Category | Plugins |
|----------|---------|
| **Linting/Formatting** | ALE, Black, vim-autoformat, Prettier |
| **Language Support** | vim-go, rust.vim, typescript-vim, python-syntax, vim-terraform |
| **Navigation** | NERDTree, CtrlP, Unite-outline |
| **Git** | vim-fugitive |
| **Editing** | auto-pairs, vim-surround, vim-commentary |
| **UI** | vim-airline, vim-colorschemes (badwolf) |
| **Completion** | ALE completion (tsserver, pylsp) |

### ALE Configuration

| Language | Linters | Fixers |
|----------|---------|--------|
| JavaScript/TypeScript | ESLint | Prettier |
| Python | ruff, mypy | ruff_format, black |
| Terraform | terraform, tflint | terraform fmt |

Fix on save is enabled.

---

## Tmux Configuration

### Prefix Key

`C-a` (Control-a)

### TPM Plugins

- tmux-sensible
- tmux-yank
- tmux-copycat
- tmux-open

Install TPM:

```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

Then press `C-a I` to install plugins.

### Status Bar

- **Left**: Battery indicator + Claude monitor status
- **Right**: Session name, time, date
- **Colors**: Black bg, cyan/blue/magenta accents

---

## Git Configuration

### Core Settings

- Editor: vim
- Pull: rebase mode
- Push: simple with auto-setup remote
- Fetch: prune enabled
- Default branch: master

### Notable Aliases

| Alias | Command |
|-------|---------|
| `l` | Decorated log (colorized) |
| `lg` | Graph log |
| `lt` | Last 24h log |
| `ds` | Diff staged |
| `uncommit` | Soft reset HEAD^ |
| `replace` | Global find/replace |

---

## Claude Code Utilities

### Commands

All accessed via `claude-util <command>`:

| Command | Description |
|---------|-------------|
| `status` | Health check (snapshots + watcher) |
| `fix` | Fix corrupted snapshots + restart watcher |
| `nuke` | Delete all snapshots (emergency) |
| `watch [cmd]` | Watcher management (start\|stop\|status) |
| `clean [cmd]` | Cleanup management (fix\|delete\|status) |
| `perm [cmd]` | Permissions management |
| `monitor [cmd]` | Instance monitoring |

### Monitor Subcommands

| Command | Description |
|---------|-------------|
| `start` | Start background daemon |
| `stop` | Stop daemon + kill orphaned processes |
| `restart` | Restart daemon |
| `status` | Show monitor status |
| `list` | List all Claude instances |
| `goto <session>` | Jump to session's Claude pane |
| `back` | Switch back to running dashboard |
| `-f` | Foreground mode (simple) |
| `-fv` | Verbose dashboard (output preview) |
| `attach` | Alias for foreground mode |
| `verbosity [lvl]` | Get/set notification level (silent\|minimal\|verbose) |
| `debug [on\|off]` | Toggle debug logging (off cleans log) |
| `logs [n]` | Show last n lines of log (default: 50) |

### Monitor Features

- **Persistent Dashboard**: Jump with `1-9`, dashboard keeps running
- **Return Key**: `C-a B` (tmux binding) or `claude-util monitor back`
- **Refresh**: Press `r` to fix visual glitches
- **Debug Logging**: Off by default, enable with `debug on`
- **State Detection**: 30s idle threshold, pattern hints for prompts
- **Recovery**: `claude-util unfreeze [pane]` from another session

---

## Environment Variables

### PATH Components (ordered)

1. Homebrew (`/opt/homebrew/bin`)
2. rbenv
3. Home bin directories
4. Go paths
5. Cargo (Rust)
6. Python
7. PostgreSQL
8. Docker
9. tfenv
10. Claude

### Editor Settings

```bash
TERM=xterm-256color
EDITOR=vim
CLICOLOR=1
DISABLE_AUTO_TITLE=true  # for tmux
```

---

## Tmuxinator Projects

Located in `.tmuxinator/`. Start with `ms <project>`:

| Project | File |
|---------|------|
| bb | Bitbraid |
| df | Dotfiles |
| events | Events |
| hub | Hub |
| infra | Infrastructure |
| phones | Phones |
| research | Research |
| rvm-sls | RVM Serverless |
| sales | Sales |
| sites | Sites |

---

## Language Support

| Language | Tools |
|----------|-------|
| **Python** | python3, pip3, pylsp, ruff, black, mypy |
| **JavaScript** | Node (via nvm), npm, yarn, pnpm, ESLint, Prettier |
| **TypeScript** | tsserver, ESLint, Prettier |
| **Go** | vim-go, gopls |
| **Rust** | rust.vim, cargo |
| **Terraform** | terraform, tflint, tfenv |
| **Ruby** | rbenv |

---

## Installation

### Quick Setup

```bash
# Clone the repository
cd ~/dev
git clone <repo-url> dotfiles

# Run dotfiles setup (creates symlinks)
./scripts/dotfiles.sh

# Install Vundle and plugins
git clone git@github.com:VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
vim +PluginInstall +qall

# Install TPM
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

### Symlinked Files

The setup script creates symlinks for:

- `.bash_profile`, `.bashrc`, `.profile`
- `.git_template`, `.gitconfig`
- `.tmux.conf`, `.tmuxinator`
- `.vimrc`, `.zsh`, `.zshrc`
- `bin`
- `.terraformrc`
