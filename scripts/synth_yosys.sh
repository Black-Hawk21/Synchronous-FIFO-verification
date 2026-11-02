#!/usr/bin/env bash
#------------------------------------------------------------------------------
# synth_yosys.sh - generic synthesis of the RTL with Yosys (synthesizability
#                  check: no latches, no multiple drivers, cell statistics)
#
# Usage: scripts/synth_yosys.sh [config ...]     (default: all five configs)
# Output: results/synth/<config>.log, summary on stdout
# Exit:   0 if every configuration synthesizes and passes "check -assert"
#------------------------------------------------------------------------------
set -u
source "$(dirname "$0")/common.sh"

command -v yosys > /dev/null || die "yosys not found"
CONFIGS="${*:-$ALL_CONFIGS}"
mkdir -p "$RESULTS/synth"
status=0

printf "%-8s %-10s %-7s %-12s %-14s %s\n" config params cells "state flops" "storage flops" result
for cfg in $CONFIGS; do
  read -r w d <<< "$(config_defines "$cfg" | sed -E 's/.*WIDTH=([0-9]+).*DEPTH=([0-9]+)/\1 \2/')"
  af=$(( d > 2 ? d - 2 : d ))
  log="$RESULTS/synth/$cfg.log"
  yosys -p "read_verilog -sv $RTL_FILE;
            chparam -set DATA_WIDTH $w -set DEPTH $d -set ALMOST_FULL_LEVEL $af -set ALMOST_EMPTY_LEVEL 1 sync_fifo;
            synth -top sync_fifo -flatten; check -assert; stat" > "$log" 2>&1
  rc=$?
  # Statistics of the final "stat" command (last block in the log)
  stats="$(awk '/Printing statistics/ {buf=""} {buf = buf $0 "\n"} END {printf "%s", buf}' "$log")"
  cells=$(grep -E "Number of cells:" <<< "$stats" | awk '{print $4}')
  rflops=$(grep -E '\$_SDFF' <<< "$stats" | awk '{s += $2} END {print s + 0}')   # flops with sync reset
  sflops=$(grep -E '\$_DFFE?_[PN]+_ ' <<< "$stats" | awk '{s += $2} END {print s + 0}')   # flops without reset
  if [[ $rc -ne 0 ]]; then
    result="FAIL (see $log)"; status=1
  elif grep -i "latch inferred for signal" "$log" | grep -vqi "No latch"; then
    result="FAIL: latch inferred (see $log)"; status=1
  else
    result="OK"
  fi
  printf "%-8s %-10s %-7s %-12s %-14s %s\n" "$cfg" "W=$w D=$d" "${cells:--}" "${rflops:--}" "${sflops:--}" "$result"
done
exit $status
