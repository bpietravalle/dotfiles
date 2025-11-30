# Docker utilities

restart_docker() {
  if [[ "$(uname)" == "Darwin" ]]; then
    open -a "Docker Desktop"
  else
    sudo systemctl restart docker
  fi
}
