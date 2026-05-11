#!/bin/bash

killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 1; done

polybar primary &
if xrandr --listmonitors | grep -q "HDMI-1-0"; then
    polybar secondary &
fi
