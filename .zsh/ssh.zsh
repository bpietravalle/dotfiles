SSH_USER_CONFIG=$HOME/.ssh/config
SSH_ID_DIR=$HOME/.ssh

if [[ -z "$SSH_CONNECTION" ]]; then

  # Avoid actions when using Mac OS Keychain
  if [[ ! $SSH_AUTH_SOCK =~ "com\.apple\.launchd" ]]; then
    export SSH_AGENT_PID=$(find_pid 'ssh-agent')

    if [[ -z "$SSH_AGENT_PID" ]]; then
      export SSH_AGENT_PID=$(find_pid '.*ssh-agent')
    fi

    check_pid_running $SSH_AGENT_PID
    if [[ "$?" -gt 0 ]]; then
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

  if [[ -n $(ls $SSH_ID_DIR) ]]; then
    # get ssh-add command and the keys in ssh-agent
    SSH_ADD=$(which ssh-add)
    keys=$($SSH_ADD -l | cut -d " " -f 3)

    # go through all files in $SSH_ID_DIR
    add_key=()
    for k_file in `ls $SSH_ID_DIR/*`; do
      if [[ "$k_file" =~ "rsa" && ! "$k_file" =~ ".pub" ]]; then
        if [[ ! $keys =~ $k_file ]]; then
          add_key[$(($#add_key +1))]=$k_file
        fi
      fi
    done
    if [[ -n "$add_key" ]]; then
      {$SSH_ADD $add_key } &>/dev/null
    fi

    unset SSH_ADD
    unset add_key
    unset keys
  fi
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
### new script but doesn't handle keychain logic
# SSH_USER_CONFIG=$HOME/.ssh/config
# SSH_ID_DIR=$HOME/.ssh

# if [[ -z "$SSH_CONNECTION" ]]; then

#   # Check if the SSH agent is running, otherwise start it
#   if [[ -z "$SSH_AGENT_PID" ]] || ! ps -p "$SSH_AGENT_PID" > /dev/null; then
#     echo "Starting new SSH agent..."
#     eval "$(ssh-agent -s)"
#   fi

#   # Check if the SSH_AUTH_SOCK is set correctly
#   if [[ -z "$SSH_AUTH_SOCK" ]]; then
#     export SSH_AUTH_SOCK=$(find /tmp -type s -iname 'agent.*' 2>/dev/null | head -n 1)
#   fi

#   # Add all private keys from SSH_ID_DIR if not already added
#   for key in "$SSH_ID_DIR"/*.pem; do
#     if [[ -f "$key" ]]; then
#       if ! ssh-add -l | grep -q "$key"; then
#         echo "Adding SSH key: $key"
#         ssh-add "$key"
#       fi
#     fi
#   done
# fi

# add_ssh_key_by_fpath() {
#   local key_path="$1"  # First argument: path to the SSH key file

#   # Check if the SSH key file exists
#   if [[ ! -f "$key_path" ]]; then
#     echo "Error: SSH key file not found at '$key_path'. Please provide a valid path."
#     return 1
#   fi
#   chmod 600 "$key_path"

#   # Start the SSH agent if it's not already running
#   if [[ -z "$SSH_AUTH_SOCK" ]]; then
#     echo "Starting ssh-agent..."
#     eval "$(ssh-agent -s)"
#   fi

#   # Add the SSH key to the agent
#   ssh-add "$key_path"

#   # Check if the key was added successfully
#   if [[ $? -eq 0 ]]; then
#     echo "SSH key '$key_path' added successfully."
#   else
#     echo "Error: Failed to add SSH key '$key_path'."
#   fi
# }

