#!/bin/bash
CAP_AT=80          # °C: cap GPU clocks
UNCAP_AT=60        # °C: remove clock cap
CAP_MHZ=1800       # capped max GPU clock (you were running ~2320 MHz)
PAUSE_AT=90        # °C: pause all running containers
RESUME_AT=80       # °C: resume the containers we paused
EMERGENCY_AT=93    # °C: still rising with everything paused -> clean poweroff

STATE=/run/thermal-guard.paused       # IDs of containers this script paused
CAPPED=/run/thermal-guard.capped      # exists while clocks are capped
CAP_FAILED=/run/thermal-guard.capfail # cap unsupported (warn only once)

hottest() {
  local t0 t5
  t0=$(( $(cat /sys/class/thermal/thermal_zone0/temp) / 1000 ))   # TSOC
  t5=$(( $(cat /sys/class/thermal/thermal_zone5/temp) / 1000 ))   # TGPU
  echo $(( t0 > t5 ? t0 : t5 ))
}

names() { docker inspect -f '{{.Name}}' "$@" 2>/dev/null | tr -d / | paste -sd' '; }

cap_clocks() {
  [ -f "$CAPPED" ] || [ -f "$CAP_FAILED" ] && return
  if nvidia-smi -lgc 0,"$CAP_MHZ" >/dev/null 2>&1; then
    touch "$CAPPED"
    logger -t thermal-guard "CAPPED clocks to ${CAP_MHZ}MHz at ${1}C"
  else
    touch "$CAP_FAILED"
    logger -t thermal-guard "WARNING: clock cap not supported - relying on pause only"
  fi
}

uncap_clocks() {
  [ -f "$CAPPED" ] || return
  nvidia-smi -rgc >/dev/null 2>&1
  rm -f "$CAPPED"
  logger -t thermal-guard "UNCAPPED clocks at ${1}C"
}

pause_all() {
  local ids
  ids=$(docker ps -q --filter status=running)
  [ -z "$ids" ] && return
  docker pause $ids >/dev/null 2>&1
  echo "$ids" >> "$STATE"
  logger -t thermal-guard "PAUSED at ${1}C: $(names $ids)"
}

resume_all() {
  local ids
  [ -s "$STATE" ] || return
  ids=$(sort -u "$STATE")
  docker unpause $ids >/dev/null 2>&1
  logger -t thermal-guard "RESUMED at ${1}C: $(names $ids)"
  rm -f "$STATE"
}

cleanup() { t=$(hottest); resume_all "$t"; uncap_clocks "$t"; exit 0; }
trap cleanup TERM INT

logger -t thermal-guard "started: cap>=${CAP_AT}C uncap<=${UNCAP_AT}C pause>=${PAUSE_AT}C resume<=${RESUME_AT}C emergency>=${EMERGENCY_AT}C"
while true; do
  temp=$(hottest)

  # Last resort
  if [ "$temp" -ge "$EMERGENCY_AT" ]; then
    logger -t thermal-guard "EMERGENCY ${temp}C with containers paused - clean poweroff"
    sync
    systemctl poweroff
    exit 0
  fi

  # Stage 1: clock cap
  if [ "$temp" -ge "$CAP_AT" ]; then
    cap_clocks "$temp"
  elif [ "$temp" -le "$UNCAP_AT" ]; then
    uncap_clocks "$temp"
  fi

  # Stage 2: pause containers
  if [ "$temp" -ge "$PAUSE_AT" ]; then
    pause_all "$temp"
  elif [ "$temp" -le "$RESUME_AT" ]; then
    resume_all "$temp"
  fi

  sleep 2 & wait $!
done
