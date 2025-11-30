SSH_USER_CONFIG=$HOME/.ssh/config
SSH_ID_DIR=$HOME/.ssh

# Helper functions
_find_pid() { pgrep -x "$1" 2>/dev/null | head -1; }
_check_pid_running() { [[ -n "$1" ]] && kill -0 "$1" 2>/dev/null; }

# Avoid actions when using Mac OS Keychain
if [[ ! $SSH_AUTH_SOCK =~ "com\.apple\.launchd" ]]; then
  export SSH_AGENT_PID=$(_find_pid 'ssh-agent')

  if [[ -z "$SSH_AGENT_PID" ]]; then
    export SSH_AGENT_PID=$(pgrep -f 'ssh-agent' 2>/dev/null | head -1)
  fi

  if ! _check_pid_running "$SSH_AGENT_PID"; then
    unset SSH_AGENT_PID

    export SSH_AUTH_SOCK=$HOME/.ssh/auth_socket

    # check if there is an old socket file and remove it
    if [[ -w "$SSH_AUTH_SOCK" ]]; then
      rm $SSH_AUTH_SOCK
    fi

    eval $(ssh-agent -a $SSH_AUTH_SOCK -s)
  else
    export SSH_AUTH_SOCK=$(find /tmp -type s -iname 'agent.*' 2>/dev/null)
  fi
fi

# Add SSH keys not already in agent
if [[ -d "$SSH_ID_DIR" ]]; then
  SSH_ADD=$(command -v ssh-add)
  keys=$($SSH_ADD -l 2>/dev/null | cut -d " " -f 3)

  add_key=()
  for k_file in "$SSH_ID_DIR"/*; do
    [[ -f "$k_file" ]] || continue
    if [[ "$k_file" =~ "rsa" && ! "$k_file" =~ ".pub" ]]; then
      if [[ ! $keys =~ $k_file ]]; then
        add_key+=("$k_file")
      fi
    fi
  done

  if [[ ${#add_key[@]} -gt 0 ]]; then
    $SSH_ADD "${add_key[@]}" &>/dev/null
  fi

  unset SSH_ADD add_key keys
fi

add_ssh_key_by_fpath() {
  local key_path="$1"  # First argument: path to the SSH key file

  # Check if the SSH key file exists
  if [[ ! -f "$key_path" ]]; then
    echo "Error: SSH key file not found at '$key_path'. Please provide a valid path."
    return 1
  fi
  chmod 600 $key_path

  # Start the SSH agent if it's not already running
  if [[ -z "$SSH_AUTH_SOCK" ]]; then
    echo "Starting ssh-agent..."
    eval "$(ssh-agent -s)"
  fi

  # Add the SSH key to the agent
  ssh-add "$key_path"

  # Check if the key was added successfully
  if [[ $? -eq 0 ]]; then
    echo "SSH key '$key_path' added successfully."
  else
    echo "Error: Failed to add SSH key '$key_path'."
  fi
}
list_known_hosts() {
  local known_hosts="$HOME/.ssh/known_hosts"
  if [[ ! -f "$known_hosts" ]]; then
        echo "Error: $known_hosts does not exist"
        return 1
    fi
    cut -d ' ' -f1 $known_hosts | sort -u
}

remove_known_host() {
    if [[ -z "$1" ]]; then
        echo "Usage: remove_known_host <ip_pattern>"
        return 1
    fi

    local ip_pattern="$1"
    local known_hosts="$HOME/.ssh/known_hosts"
    if [[ ! -f "$known_hosts" ]]; then
        echo "Error: $known_hosts does not exist"
        return 1
    fi
    cp "$known_hosts" "${known_hosts}.bak"
    echo "Removing entries matching: $ip_pattern"
    grep -n "$ip_pattern" "$known_hosts" || echo "No matching entries found"
    if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "/$ip_pattern/d" "$known_hosts"
    else
        sed -i "/$ip_pattern/d" "$known_hosts"
    fi
}
