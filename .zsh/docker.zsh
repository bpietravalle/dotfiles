function restart_docker () {
  # on mac
  os_run "
  safe_bg_start 'Docker Desktop'
  "
  # on linux
}

