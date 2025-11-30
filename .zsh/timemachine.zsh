#!/bin/zsh
EXCLUDE_NAMES=(
    ".terraform"
    "node_modules"
    ".cache"
    ".gradle"
    ".m2"
    ".docker"
    ".venv"
    ".vscode"
    ".npm"
    ".git"
    ".yarn"
    ".oh-my-zsh"
    ".nvm"
    ".config/yarn"
    ".yarn"
    ".ipynb_checkpoints"
    ".cache/pip"
    ".conda"
    ".condarc"
    ".keras"
    ".cache/torch"
    ".cache/huggingface"
)
EXCLUDE_PATHS=(
    "$HOME/Library"
    "$HOME/Applications"
    "$HOME/System"
    "$HOME/Volumes"
    "$HOME/.Trash"
    "$HOME/Google Drive/"
    "$HOME/RVM-GDrive/"
)

# Function to build the find exclusion string for paths
build_exclusion_string() {
    local exclusion_string=""
    for path in "${EXCLUDE_PATHS[@]}"; do
        exclusion_string="$exclusion_string -path \"$path\" -o"
    done
    # Trim trailing '-o' from the exclusion string
    echo "${exclusion_string% -o}"
}

# Function to find directories by name and exclude them from Time Machine
exclude_from_timemachine() {
    local exclusion_string=$(build_exclusion_string)
    
    for name in "${EXCLUDE_NAMES[@]}"; do
        echo "Searching for $name directories in $HOME"
        
        eval "find \"$HOME\" \( $exclusion_string \) -prune -o -type d -name \"$name\" -prune" | while read -r dir; do
            tmutil addexclusion "$dir"
        done
    done
}

# exclude_from_timemachine() {
#     for name in "${EXCLUDE_NAMES[@]}"; do
#         echo "Searching for $name directories in $HOME"
#         find "$HOME" -type d -name "$name" -prune | while read -r dir; do
#             # echo "Excluding $dir from Time Machine backups"
#             tmutil addexclusion "$dir"
#         done
#     done
# }
