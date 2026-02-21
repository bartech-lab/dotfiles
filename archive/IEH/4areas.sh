#!/bin/bash

sleep 0.3;

for i in {1..10000};
do 

# AREAS *-4

# 1-4
xdotool mousemove 620 920;
xdotool click 1;
xdotool mousemove 450 555;
xdotool click 1;
xdotool mousemove 600 650;
xdotool click --repeat 15 --delay 200 1;

# 2-4
xdotool mousemove 500 555;
xdotool click 1;
xdotool mousemove 600 650;
xdotool click --repeat 15 --delay 200 1;

# 3-4
xdotool mousemove 550 555;
xdotool click 1;
xdotool mousemove 600 650;
xdotool click --repeat 15 --delay 200 1;

# 4-4
xdotool mousemove 600 555;
xdotool click 1;
xdotool mousemove 600 650;
xdotool click --repeat 15 --delay 200 1;

# 5-4
xdotool mousemove 450 580;
xdotool click 1;
xdotool mousemove 600 650;
xdotool click --repeat 15 --delay 200 1;

# 6-4
xdotool mousemove 500 580;
xdotool click 1;
xdotool mousemove 600 650;
xdotool click --repeat 25 --delay 200 1;

# 4-8
xdotool mousemove 600 555;
xdotool click 1;
xdotool mousemove 600 700;
xdotool click --repeat 15 --delay 200 1;
xdotool mousemove 440 420;
sleep 55;

sleep 400;


# NITRO
xdotool mousemove 450 940;
xdotool click 1;
xdotool mousemove 530 520;
xdotool click 1;
xdotool mousemove 435 550;
xdotool click 1;
xdotool mousemove 620 640;
xdotool key --repeat 5 --delay 500 --repeat-delay 1000 M+U

xdotool mousemove 440 420;

done
