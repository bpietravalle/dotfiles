#!/bin/sh

# Ensure docker adds symlink to home dir
# It hasn't for past few installs
DOCKER_BIN_DIR="/Applications/Docker.app/Contents/Resources/bin"
TARGET_DIR="$HOME/.docker/bin"

# DOCKER_FILES=$(bin)


if [ -L "$TARGET_DIR" ]; then
  echo "Symlink for $TARGET_DIR already exists. Skipping."
else
  ln -s "$DOCKER_BIN_DIR" "$TARGET_DIR"
echo "Created symlink for $TARGET_DIR."
fi
ls -ll $TARGET_DIR
echo "Symlink setup complete."

