#!/bin/bash

# Clean Cache
sudo pacman -Scc
# Move old keys
sudo mv /etc/pacman.d/gnupg /etc/pacman.d/gnupg.old
# Init new keyring
sudo pacman-key --init
# Populate keyring
sudo pacman-key --populate archlinux manjaro
# Update system
sudo pacman -Syu
