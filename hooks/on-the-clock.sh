#!/bin/bash
# On Air hook: passes camera, microphone and screen-share sessions on to On
# the Clock, which decides whether they are a meeting to time or book.
# Install with
#   omarchy hook install on-air ~/.config/omarchy/plugins/s-curve.on-the-clock/hooks/on-the-clock.sh
# Arguments: start <camera|mic|screen> <app> <start> | stop <camera|mic|screen> <app> <start> <end>
# (epoch seconds). Without On the Clock running this does nothing.
qs ipc -p /usr/share/omarchy/shell call ontheclock onAir "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-0}" >/dev/null 2>&1 || true
