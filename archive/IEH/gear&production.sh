#!/bin/bash


# WEAR GEAR
sleep 0.3;

xdotool mousemove 700 920;
xdotool click 1;
xdotool mousemove 435 520;
xdotool click 1;

sleep 0.2;
xdotool mousemove 635 555;
xdotool click 1;

xdotool mousemove 700 600;
xdotool click 1;
xdotool mousemove 700 670;
xdotool click 1;
xdotool mousemove 635 670;
xdotool click 1;
xdotool mousemove 575 670;
xdotool click 1;
xdotool mousemove 515 670;
xdotool click 1;
xdotool mousemove 455 670;
xdotool click 1;

xdotool mousemove 440 420;
sleep 0.5;
xdotool mousemove 660 555;
xdotool click 1;

xdotool mousemove 700 600;
xdotool click 1;
xdotool mousemove 700 670;
xdotool click 1;
xdotool mousemove 575 670;
xdotool click 1;
xdotool mousemove 515 670;
xdotool click 1;
xdotool mousemove 455 670;
xdotool click 1;

xdotool mousemove 440 420;
sleep 0.5;
xdotool mousemove 690 555;
xdotool click 1;

xdotool mousemove 635 600;
xdotool click 1;
xdotool mousemove 575 600;
xdotool click 1;
xdotool mousemove 455 600;
xdotool click 1; 

xdotool mousemove 440 420;
sleep 0.5;
xdotool mousemove 700 670;
xdotool click 1;
xdotool mousemove 635 670;
xdotool click 1;
xdotool mousemove 575 670;
xdotool click 1;
xdotool mousemove 515 670;
xdotool click 1;
xdotool mousemove 455 670;
xdotool click 1;


for i in {1..20};
do 

# CLICK PROD 3
sleep 1;
xdotool mousemove 635 725;
xdotool click --repeat 8 --delay 650 1;
xdotool mousemove 635 765;
xdotool click --repeat 8 --delay 650 1;
xdotool mousemove 635 800;
xdotool click --repeat 8 --delay 650 1;

xdotool mousemove 440 420;


# CLICK PROD 2
sleep 1;
xdotool mousemove 595 725;
dxotool click --repeat 8 --delay 500 1;
xdotool mousemove 595 765;
xdotool click --repeat 8 --delay 650 1;
xdotool mousemove 595 800;
xdotool click --repeat 8 --delay 650 1;

xdotool mousemove 440 420;


# UPGRADE COIN, EXP, RITUALS
sleep 1;
xdotool mousemove 690 695;
xdotool click 1;

xdotool mousemove 440 840;
xdotool click --repeat 8 --delay 650 1;
sleep 3;
xdotool mousemove 480 840;
xdotool click --repeat 8 --delay 650 1;
sleep 3;
xdotool mousemove 635 840;
xdotool click --repeat 8 --delay 650 1;
sleep 3;
xdotool mousemove 600 840;
xdotool click --repeat 8 --delay 650 1;
sleep 3;
xdotool mousemove 560 840;
xdotool click --repeat 8 --delay 650 1;

xdotool mousemove 440 420;


# CLICK PROD 1
sleep 1;
xdotool mousemove 555 725;
xdotool click --repeat 8 --delay 650 1;
xdotool mousemove 555 765;
xdotool click --repeat 8 --delay 650 1;
xdotool mousemove 555 800;
xdotool click --repeat 8 --delay 650 1;

xdotool mousemove 440 420;

done
