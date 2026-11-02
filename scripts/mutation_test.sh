#!/usr/bin/env bash
#------------------------------------------------------------------------------
# mutation_test.sh - prove the testbench detects real bugs
#
# Builds each mutant from scripts/mutate_rtl.py (one injected bug per copy of
# the RTL), runs the SV test list against it and reports which checker caught
# it. A mutant is killed when at least one test fails.
#
# Usage: scripts/mutation_test.sh [options]
#       --configs "LIST"   configurations       (default: "default npot")
#       --tests "LIST"     tests per mutant     (default: all directed tests +
#                                                random_balanced_test + random_write_heavy_test)
#       --seed N           seed for random tests (default: 1)
#       --sim NAME         verilator|questa|vcs|xcelium
#   -h, --help
#
# Output: results/mutation/<sim>_<timestamp>/summary.txt (+ logs)
# Exit:   0 if every mutant was killed in at least one configuration.
#------------------------------------------------------------------------------
set -u
source "$(dirname "$0")/common.sh"

CONFIGS="default npot"
TESTS="$SV_DIRECTED_TESTS random_balanced_test random_write_heavy_test"
SEED=1

usage() { sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --configs) CONFIGS="$2"; shift 2 ;;
    --tests)   TESTS="$2"; shift 2 ;;
    --seed)    SEED="$2"; shift 2 ;;
    --sim)     SIM="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown option '$1'" >&2; usage 2 ;;
  esac
done
export SIM

OUT="$RESULTS/mutation/${SIM}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT"
python3 "$ROOT/scripts/mutate_rtl.py" make "$ROOT/rtl/sync_fifo.sv" "$OUT/rtl" || exit 2

info "Mutation testing: sim=$SIM configs=[$CONFIGS] tests/mutant=$(wc -w <<< "$TESTS")"

ROWS=()
killed_total=0; mutants_total=0
while IFS=$'\t' read -r name desc; do
  mutants_total=$((mutants_total + 1))
  row="$name"
  any_kill=0
  for cfg in $CONFIGS; do
    first=1; nfail=0; ntests=0; n_scb=0; n_sva=0; n_chk=0; compile_err=0
    for test in $TESTS; do
      ntests=$((ntests + 1))
      log="$OUT/logs/$name/$cfg/${test}.log"
      flag="--no-compile"; [[ $first -eq 1 ]] && flag=""; first=0
      RTL_FILE="$OUT/rtl/$name/sync_fifo.sv" BUILD_DIR="$OUT/build/$name/$cfg" LOG_FILE="$log" \
        "$ROOT/scripts/run_sv.sh" -t "$test" -c "$cfg" -s "$SEED" $flag > /dev/null 2>&1
      rc=$?
      [[ $rc -eq 2 ]] && { compile_err=1; break; }
      if [[ $rc -ne 0 ]]; then
        nfail=$((nfail + 1))
        # Which checkers reported this failure
        grep -q "\[FAIL\]"            "$log" && n_scb=$((n_scb + 1))
        grep -q "\[SVA\]"             "$log" && n_sva=$((n_sva + 1))
        grep -q "\[CHECK\].*expected" "$log" && n_chk=$((n_chk + 1))
      fi
    done
    if [[ $compile_err -eq 1 ]]; then
      row+=$'\t'"compile error"
    elif [[ $nfail -gt 0 ]]; then
      any_kill=1
      row+=$'\t'"KILLED $nfail/$ntests (scoreboard $n_scb, SVA $n_sva, checks $n_chk)"
    else
      row+=$'\t'"survived 0/$ntests"
    fi
  done
  [[ $any_kill -eq 1 ]] && killed_total=$((killed_total + 1))
  ROWS+=("$row"$'\t'"$desc")
  info "$(printf '%-28s' "$name") $(cut -f2- <<< "$row" | tr '\t' '|')"
done < <(python3 "$ROOT/scripts/mutate_rtl.py" list)

{
  echo "Mutation testing summary"
  echo "  simulator : $SIM"
  echo "  date      : $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "  configs   : $CONFIGS"
  echo "  tests     : $TESTS (seed $SEED)"
  echo "  killed    : $killed_total of $mutants_total mutants"
  echo
  echo "KILLED f/n = f of n tests failed; (scoreboard a, SVA b, checks c) = number of"
  echo "failing tests in which the scoreboard / an assertion / a directed check reported it."
  echo
  header="| Mutant |"; sep="|---|"
  for cfg in $CONFIGS; do header+=" $cfg ($(config_desc "$cfg")) |"; sep+="---|"; done
  echo "$header Injected bug |"
  echo "$sep---|"
  for r in "${ROWS[@]}"; do
    echo "| $(sed 's/\t/ | /g' <<< "$r") |"
  done
} > "$OUT/summary.txt"

cp "$OUT/summary.txt" "$RESULTS/mutation/latest_${SIM}.txt"
cat "$OUT/summary.txt"

[[ $killed_total -eq $mutants_total ]]
