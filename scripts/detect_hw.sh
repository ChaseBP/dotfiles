#!/usr/bin/env bash
# Hardware facts for the desktop steps, printed as shell assignments:
#
#   eval "$(scripts/detect_hw.sh)"
#
# Read-only: sysfs, /proc and lspci only, so it is safe to run anywhere (and
# under --dry-run). Drivers are not our business — the CachyOS installer (chwd)
# owns those; this only decides which personal config bits apply.
#
#   HW_PRODUCT        DMI product name, for the generated file's header
#   HW_GPUS           space-separated: intel amd nvidia (display controllers)
#   HW_NVIDIA_ONLY    1 when NVIDIA is the only GPU (needs Hyprland env vars)
#   HW_INTEL_CPU      1 on Intel CPUs (thermald)
#   HW_LAPTOP         1 when a battery is present
#   HW_PANEL          internal panel connector (eDP-1), empty on desktops
#   HW_TOUCH          1 when a direct-touch / pen digitiser exists
#   HW_SCREEN_INPUTS  Hyprland names of those digitisers (pen + finger), to
#                     pin them to HW_PANEL (space-separated)
#   HW_ACCEL          1 when an IIO accelerometer exists (auto-rotate)
#   HW_TABLET_SWITCH  input device reporting SW_TABLET_MODE (2-in-1 hinge)
#   HW_TABLET_OFF     Hyprland names of the internal keyboard + touchpad, to
#                     disable while folded (space-separated)
#   HW_XPPEN          1 when an XP-Pen tablet (USB vendor 28bd) is plugged in
set -uo pipefail

emit() { printf '%s=%q\n' "$1" "$2"; }

# Hyprland names input devices by lowercasing and replacing spaces with '-'.
hypr_name() { printf '%s' "$1" | tr '[:upper:] ' '[:lower:]-'; }

emit HW_PRODUCT "$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"

gpus=""
if command -v lspci >/dev/null 2>&1; then
  # class 0300 VGA, 0302 3D, 0380 display — vendor ids are stable, names are not
  while read -r vendor; do
    case "$vendor" in
      8086) gpus="$gpus intel" ;;
      1002) gpus="$gpus amd" ;;
      10de) gpus="$gpus nvidia" ;;
    esac
  done < <(lspci -n | awk '$2 ~ /^03(00|02|80):$/ { split($3, id, ":"); print id[1] }' | sort -u)
fi
gpus="${gpus# }"
emit HW_GPUS "$gpus"
emit HW_NVIDIA_ONLY "$([ "$gpus" = nvidia ] && echo 1 || echo 0)"
emit HW_INTEL_CPU "$(grep -qm1 GenuineIntel /proc/cpuinfo && echo 1 || echo 0)"
emit HW_LAPTOP "$(compgen -G '/sys/class/power_supply/BAT*' >/dev/null && echo 1 || echo 0)"

panel=""
for c in /sys/class/drm/card*-eDP-* /sys/class/drm/card*-LVDS-*; do
  [ -e "$c" ] || continue
  panel="${c##*/}"; panel="${panel#card*-}"; break
done
emit HW_PANEL "$panel"

accel=0
for d in /sys/bus/iio/devices/iio:device*; do
  [ -e "$d/in_accel_x_raw" ] && { accel=1; break; }
done
emit HW_ACCEL "$accel"

# External drawing tablets (XP-Pen's raw interface among them) can claim
# INPUT_PROP_DIRECT too; a built-in screen digitiser is never on a USB port the
# firmware marks "removable".
on_removable_port() { # $1=device block
  local d
  d=$(sed -n 's/^S: Sysfs=//p' <<<"$1")
  d="/sys$d"
  while [ "$d" != /sys ] && [ "$d" != / ]; do
    [ -f "$d/removable" ] && { [ "$(cat "$d/removable")" = removable ]; return; }
    d=$(dirname "$d")
  done
  return 1
}

# /proc/bus/input/devices: one blank-line-separated block per device.
# PROP bit 1 = INPUT_PROP_DIRECT (touchscreens, pen digitisers);
# SW bit 1 = SW_TABLET_MODE (the convertible hinge).
touch=0 switch="" off=() direct=()
while IFS= read -r -d '' block; do
  name=$(sed -n 's/^N: Name="\(.*\)"$/\1/p' <<<"$block")
  prop=$(sed -n 's/^B: PROP=\([0-9a-f]*\)$/\1/p' <<<"$block")
  sw=$(sed -n 's/^B: SW=\([0-9a-f ]*\)$/\1/p' <<<"$block" | awk '{print $NF}')
  if [ -n "$prop" ] && (( 0x$prop & 2 )) && ! on_removable_port "$block"; then
    touch=1; direct+=("$(hypr_name "$name")")
  fi
  [ -z "$switch" ] && [ -n "$sw" ] && (( 0x$sw & 2 )) && switch="$name"
  case "$name" in
    "AT Translated Set 2 keyboard"|*[Tt]ouchpad) off+=("$(hypr_name "$name")") ;;
  esac
done < <(awk 'BEGIN{RS=""; ORS="\0"} {print}' /proc/bus/input/devices 2>/dev/null)
emit HW_TOUCH "$touch"
emit HW_SCREEN_INPUTS "$(printf '%s\n' "${direct[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')"
emit HW_TABLET_SWITCH "$switch"
emit HW_TABLET_OFF "$(printf '%s\n' "${off[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')"

xppen=0
for v in /sys/bus/usb/devices/*/idVendor; do
  [ "$(cat "$v" 2>/dev/null)" = 28bd ] && { xppen=1; break; }
done
emit HW_XPPEN "$xppen"
