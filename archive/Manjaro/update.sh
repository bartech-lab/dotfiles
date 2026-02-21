#!/bin/bash

# Update system (w/o AUR)
sudo pacman -Syu --noconfirm
# Update AUR packages
pamac upgrade -a --no-confirm
# List of all installed packages. Save to Nextcloud
pacman -Qqett > "/home/bart/Nextcloud/pacman.txt"
