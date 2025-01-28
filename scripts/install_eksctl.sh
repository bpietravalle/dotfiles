#!/bin/bash
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
ARCH=arm64
PLATFORM=$(uname -s)_$ARCH

curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"

TMP_DIR=~/Downloads/
tar -xzf eksctl_$PLATFORM.tar.gz -C $TMP_DIR && rm eksctl_$PLATFORM.tar.gz

mv $TMP_DIR/eksctl ~/.local
