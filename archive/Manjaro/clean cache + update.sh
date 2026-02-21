#!/bin/bash

# Clean Cache
sudo pacman -Sc
# Update system (w/o AUR)
sudo pacman -Syu --noconfirm
# Update AUR packages
pamac upgrade -a --no-confirm

