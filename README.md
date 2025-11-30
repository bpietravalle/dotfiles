# Dotfiles

Personal shell, editor, and terminal configuration.

## What's Included

- **Zsh** - Modular configuration with 18 modules
- **Vim** - 40+ plugins via Vundle, ALE for linting/LSP
- **Tmux** - vim-style navigation, TPM plugins, battery indicator
- **Git** - Aliases, hooks, ctags integration
- **Claude Code** - Utilities for monitoring multiple instances

## Quick Start

```bash
# Clone
cd ~/dev
git clone <repo-url> dotfiles

# Install symlinks
./scripts/dotfiles.sh

# Install Vim plugins
git clone git@github.com:VundleVim/Vundle.vim.git ~/.vim/bundle/Vundle.vim
vim +PluginInstall +qall
```

## Documentation

- **[Quick Reference](docs/REFERENCE.md)** - Keyboard shortcuts, common commands
- **[Configuration Guide](docs/CONFIGURATION.md)** - Detailed setup and customization

## Structure

```
dotfiles/
├── .zshrc              # Zsh entry point
├── .zsh/               # Modular zsh config
├── .vimrc              # Vim configuration
├── .tmux.conf          # Tmux configuration
├── .tmuxinator/        # Project layouts
├── .gitconfig          # Git configuration
├── bin/                # User scripts
├── scripts/            # Installation scripts
└── docs/               # Documentation
```

## Key Bindings

| Context | Binding | Action |
|---------|---------|--------|
| Tmux | `C-a` | Prefix key |
| Tmux | `C-a -` | Split horizontal |
| Tmux | `C-a \` | Split vertical |
| Tmux | `C-a h/j/k/l` | Navigate panes |
| Vim | `\w` | Save file |
| Vim | `\gd` | Go to definition |
| Vim | `C-n` | Toggle NERDTree |

## Claude Code Utilities

Monitor multiple Claude instances across tmux sessions:

```bash
claude-util monitor -fv    # Verbose dashboard
claude-util monitor list   # List instances
C-a B                      # Return to monitor
```

See [docs/REFERENCE.md](docs/REFERENCE.md) for full command reference.
