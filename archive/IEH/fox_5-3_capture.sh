#!/bin/bash

sleep 0.3;

# GO TO AREA 5-3

for i in {1..100000};
do 

# LOOP TO MEET NITRO FREQUENCY AND QUANTITY
for i in {1..81};
do 

# CRAFT NETS
sleep 0.3;
xdotool mousemove 450 940;
xdotool click 1;
xdotool mousemove 530 520;
xdotool click 1;
xdotool mousemove 575 550;
xdotool click 1;
xdotool mousemove 710 690;
xdotool click --repeat 4 --delay 700 3;


# CAPTURE
xdotool mousemove 895 460;
xdotool click --repeat 190 --delay 100 3;


# UPGRADE ALCHEMY CAP
sleep 0.3;
xdotool mousemove 450 940;
xdotool click 1;
xdotool mousemove 530 520;
xdotool click 1;

    # 1ML
xdotool mousemove 530 565;
xdotool click 1;
xdotool mousemove 720 600;
xdotool click 1;

xdotool mousemove 440 420;

done


# NITRO
sleep 0.3;
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
