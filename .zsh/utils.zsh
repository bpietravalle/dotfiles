os_run() {
  # Check if both arguments are provided
  if [[ -z "$1" ]]; then
    echo "First argument (macOS function) is missing. Pass ':' as first arg"
    return 1
  fi

  # Determine the operating system
  case "$(uname -s)" in
    Darwin)
      # macOS
      eval "$1"
      ;;
    Linux)
      # Linux
      if [[ -n "$2" ]]; then
        eval "$2"
      fi
      ;;
    *)
      # Unknown OS
      echo "Unsupported OS: $(uname -s)"
      return 1
      ;;
  esac
}

safe_bg_start() {
  # Check if a program name is provided
  if [[ -z "$1" ]]; then
    echo "Error: No program name provided."
    return 1
  fi

  # Check if the program is installed and available in the PATH
  if ! command -v "$1" &> /dev/null; then
    echo "Error: Program '$1' not found."
    return 1
  fi

  # Start the program in the background
  nohup "$1" &>/dev/null &

  # Inform the user that the program has been started
  echo "Program '$1' started in the background."
}

copy_and_anonymize_env() {
    # Check if .env file exists in the current directory
    if [[ ! -f .env ]]; then
        echo "Error: .env file not found in the current directory." >&2
        return 1
    fi

    # Copy .env to .env.example
    cp .env .env.example

    # Replace the values of all environment variables with the word "example"
    sed -i '' -E 's/=.*/=example/' .env.example

    echo ".env file copied to .env.example with values replaced by 'example'."
}

# To use the function, just call it in the directory with the .env file
# copy_and_anonymize_env

