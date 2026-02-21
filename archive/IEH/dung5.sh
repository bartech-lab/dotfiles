#!/bin/bash


# CLICK ON DUNGEON 5
sleep 0.3;
xdotool mousemove 620 920;
xdotool click 1;
xdotool mousemove 650 795;
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

done
