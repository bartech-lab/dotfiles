#!/bin/bash

sleep 0.3;

for i in {1..100000};
do 

# PERFORMANCE MODE ON
sleep 0.3;
xdotool mousemove 705 940;
xdotool click 1;
xdotool mousemove 430 785;
xdotool click 1;

xdotool mousemove 440 420;


sleep 600;
# PERFORMANCE MODE OFF
sleep 0.3;
xdotool mousemove 705 940;
xdotool click 1;
xdotool mousemove 430 785;
xdotool click 1;


# NITRO
sleep 0.3;
xdotool mousemove 450 940;
xdotool click 1;
xdotool mousemove 525 525;
xdotool click 1;
xdotool mousemove 435 550;
xdotool click 1;
xdotool mousemove 620 640;
xdotool key --repeat 6 --delay 500 --repeat-delay 1000 M+U

done
