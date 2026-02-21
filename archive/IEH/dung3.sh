#!/bin/bash


# CLICK ON DUNGEON 3
sleep 0.3;
xdotool mousemove 620 920;
xdotool click 1;
xdotool mousemove 550 795;
xdotool click 1;

xdotool mousemove 440 420;

for i in {1..1000};
do 

# NITRO
sleep 1800;
xdotool mousemove 450 940;
xdotool click 1;
xdotool mousemove 530 520;
xdotool click 1;
xdotool mousemove 435 550;
xdotool click 1;
xdotool mousemove 620 640;
xdotool key --repeat 18 --delay 500 --repeat-delay 1000 M+U

xdotool mousemove 440 420;

# SLIME BANK CAP
sleep 0.3;
xdotool mousemove 445 920;
xdotool click 1;
xdotool mousemove 610 880;
xdotool click 1;
xdotool mousemove 595 770;
xdotool click --repeat 6 --delay 300 3;

xdotool mousemove 440 420;

done
