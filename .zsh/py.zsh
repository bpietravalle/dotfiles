# 1) Print the current git repo root (or error)
git_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
  else
    echo "Not in a git repository" >&2
    return 1
  fi
}
# 2) Check if current dir is a Python project
is_python_project() {
  [[ -f "pyproject.toml" || -f "requirements.txt" || -f "setup.py" || -f "setup.cfg" || -f "uv.lock" ]]
}

# 3) Activate venv if present
activate_venv() {
  if is_python_project; then
    if [[ -f ".venv/bin/activate" ]]; then
      echo "Activating venv from .venv"
      source ".venv/bin/activate"
    else
      echo "No .venv found in $(pwd)"
    fi
  else
    echo "Not a Python project in $(pwd)"
  fi
}

# 4) Clean caches in current dir if project
clean_py_project() {
  if is_python_project; then
    echo "Cleaning project in $(pwd)"
    find . -type d -name "__pycache__" -exec rm -rf {} +
    find . -type f -name ".DS_Store" -exec rm -rf {} +
    rm -rf .mypy_cache .pytest_cache .ruff_cache
  else
    echo "Not a Python project in $(pwd)"
  fi
}

