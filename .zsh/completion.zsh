# Third party completions


# add in zsh-completions
autoload -Uz compinit && compinit
zmodload -i zsh/complist

# Added completions for specific libraries (with guards)
command -v pipx &>/dev/null && command -v register-python-argcomplete &>/dev/null && eval "$(register-python-argcomplete pipx)"
command -v policy_sentry &>/dev/null && eval "$(_POLICY_SENTRY_COMPLETE=source policy_sentry)"
command -v eksctl &>/dev/null && eval "$(eksctl completion zsh)"
command -v kubectl &>/dev/null && eval "$(kubectl completion zsh)"

# temporary debug
# zstyle ':completion:*' verbose yes
# zstyle ':completion:*' format 'Completing %d'
# zstyle ':completion:*' debug yes

# man zshcontrib
zstyle ':vcs_info:*' actionformats '%F{5}(%f%s%F{5})%F{3}-%F{5}[%F{2}%b%F{3}|%F{1}%a%F{5}]%f '
zstyle ':vcs_info:*' formats '%F{5}(%f%s%F{5})%F{3}-%F{5}[%F{2}%b%F{5}]%f '
zstyle ':vcs_info:*' enable git #svn cvs 

# Enable completion caching, use rehash to clear
zstyle ':completion::complete:*' use-cache on
zstyle ':completion::complete:*' cache-path ~/.zsh/cache/$HOST

# Fallback to built in ls colors
zstyle ':completion:*' list-colors ''

# Make the list prompt friendly
zstyle ':completion:*' list-prompt '%SAt %p: Hit TAB for more, or the character to insert%s'

# Make the selection prompt friendly when there are a lot of choices
zstyle ':completion:*' select-prompt '%SScrolling active: current selection at %p%s'

# Add simple colors to kill
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

# list of completers to use
zstyle ':completion:*::::' completer _expand _complete _ignored _approximate

zstyle ':completion:*' menu select=1 _complete _ignored _approximate

# insert all expansions for expand completer
# zstyle ':completion:*:expand:*' tag-order all-expansions
 
# match uppercase from lowercase
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
 
# offer indexes before parameters in subscripts
zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters

# formatting and messages
zstyle ':completion:*' verbose yes
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*:messages' format '%d'
zstyle ':completion:*:warnings' format 'No matches for: %d'
zstyle ':completion:*:corrections' format '%B%d (errors: %e)%b'
zstyle ':completion:*' group-name ''
 
# ignore completion functions (until the _ignored completer)
zstyle ':completion:*:functions' ignored-patterns '_*'
zstyle ':completion:*:scp:*' tag-order files users 'hosts:-host hosts:-domain:domain hosts:-ipaddr"IP\ Address *'
zstyle ':completion:*:scp:*' group-order files all-files users hosts-domain hosts-host hosts-ipaddr
zstyle ':completion:*:ssh:*' tag-order users 'hosts:-host hosts:-domain:domain hosts:-ipaddr"IP\ Address *'
zstyle ':completion:*:ssh:*' group-order hosts-domain hosts-host users hosts-ipaddr
zstyle '*' single-ignored show


# ZAW styles
zstyle ':filter-select:highlight' matched fg=yellow,standout
zstyle ':filter-select' max-lines 10 # use 10 lines for filter-select
zstyle ':filter-select' max-lines -10 # use $LINES - 10 for filter-select
zstyle ':filter-select' rotate-list yes # enable rotation for filter-select
zstyle ':filter-select' case-insensitive yes # enable case-insensitive search
zstyle ':filter-select' extended-search no # see below

#compdef ssh
_ssh_hosts() {
    local -a hosts
    local -a known_hosts
    local -a config_hosts
    local line field

    # Extract hosts from known_hosts
    if [[ -r ~/.ssh/known_hosts ]]; then
        while IFS= read -r line; do
            field=${line%%[[:space:]]*}
            known_hosts+=(${(s/,/)field})
        done < ~/.ssh/known_hosts
        # Exclude entries starting with digits or '['
        known_hosts=(${known_hosts:#([0-9]*|[\[]*)})
    fi

    # Extract hosts from ssh config
    if [[ -r ~/.ssh/config ]]; then
        while IFS= read -r line; do
            if [[ $line == Host\ * ]]; then
                field=${line#Host }
                # Exclude entries with glob patterns (* or ?)
                if [[ $field != *[*?]* ]]; then
                    config_hosts+=($field)
                fi
            fi
        done < ~/.ssh/config
    fi

    hosts=(${known_hosts} ${config_hosts})
    hosts=(${(u)hosts})  # Remove duplicates

    _describe 'hosts' hosts
}

compdef _ssh_hosts ssh
compdef _ssh_hosts scp
