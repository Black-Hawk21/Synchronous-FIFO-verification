#!/usr/bin/env bash
#------------------------------------------------------------------------------
# regression.sh - run the test plan across configurations and seeds
#
# Usage: scripts/regression.sh [options]
#       --flow sv|uvm        testbench to regress           (default: sv)
#       --configs "LIST"     configurations                 (default: small default wide deep npot)
#       --seeds "LIST"       seeds for the random tests     (default: "1 2 3")
#       --stress-seeds "L"   seeds for the stress test      (default: "1 2")
#       --tests "LIST"       run only these tests (directed tests use the first seed)
#       --quick              directed tests + one random seed, no stress test
#       --sim NAME           verilator|questa|vcs|xcelium   (default: $SIM or verilator)
#   -h, --help
#
# Output: results/regression/<flow>_<sim>_<timestamp>/
#           summary.txt   per-run table, totals and merged coverage
#           results.csv   one row per run
#           logs/<config>/<test>__seed<N>.log
#         results/regression/latest_<flow>_<sim>.txt  (copy of summary.txt)
# Exit:   0 only if every compile and every run passed.
#------------------------------------------------------------------------------
set -u
source "$(dirname "$0")/common.sh"

FLOW="sv"
CONFIGS="$ALL_CONFIGS"
SEEDS="1 2 3"
STRESS_SEEDS="1 2"
TESTS=""
QUICK=0

usage() { sed -n '3,21p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flow)         FLOW="$2"; shift 2 ;;
    --configs)      CONFIGS="$2"; shift 2 ;;
    --seeds)        SEEDS="$2"; shift 2 ;;
    --stress-seeds) STRESS_SEEDS="$2"; shift 2 ;;
    --tests)        TESTS="$2"; shift 2 ;;
    --quick)        QUICK=1; shift ;;
    --sim)          SIM="$2"; shift 2 ;;
    -h|--help)      usage 0 ;;
    *) echo "Unknown option '$1'" >&2; usage 2 ;;
  esac
done
export SIM

case "$FLOW" in
  sv)  RUNNER="$ROOT/scripts/run_sv.sh"
       DIRECTED="$SV_DIRECTED_TESTS"; RANDOM_T="$SV_RANDOM_TESTS"; STRESS="$SV_STRESS_TESTS" ;;
  uvm) RUNNER="$ROOT/scripts/run_uvm.sh"
       DIRECTED="$UVM_DIRECTED_TESTS"; RANDOM_T="$UVM_RANDOM_TESTS"; STRESS="$UVM_STRESS_TESTS" ;;
  *)   die "--flow must be sv or uvm" ;;
esac

if [[ $QUICK -eq 1 ]]; then
  SEEDS="${SEEDS%% *}"; STRESS=""; STRESS_SEEDS="(skipped)"
fi

# Build the run list: "test seed" pairs
RUNS=()
if [[ -n "$TESTS" ]]; then
  for t in $TESTS; do
    if [[ " $DIRECTED " == *" $t "* ]]; then RUNS+=("$t ${SEEDS%% *}")
    elif [[ " $STRESS " == *" $t "* ]]; then for s in $STRESS_SEEDS; do RUNS+=("$t $s"); done
    else for s in $SEEDS; do RUNS+=("$t $s"); done; fi
  done
else
  for t in $DIRECTED; do RUNS+=("$t ${SEEDS%% *}"); done
  for t in $RANDOM_T; do for s in $SEEDS; do RUNS+=("$t $s"); done; done
  for t in $STRESS;   do for s in $STRESS_SEEDS; do RUNS+=("$t $s"); done; done
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$RESULTS/regression/${FLOW}_${SIM}_${STAMP}"
mkdir -p "$OUT/logs"
CSV="$OUT/results.csv"
SUMMARY="$OUT/summary.txt"
echo "config,test,seed,result,cycles_checked,mismatches,assertion_failures,coverage_pct,seconds" > "$CSV"

info "Regression: flow=$FLOW sim=$SIM configs=[$CONFIGS] runs/config=${#RUNS[@]}"
info "Output: $OUT"

total=0; passed=0; failed=0
FAILED_LIST=()

for cfg in $CONFIGS; do
  config_defines "$cfg" > /dev/null || exit 2
  first=1
  for run in "${RUNS[@]}"; do
    read -r test seed <<< "$run"
    log="$OUT/logs/$cfg/${test}__seed${seed}.log"
    compile_flag="--no-compile"
    [[ $first -eq 1 ]] && compile_flag=""
    first=0

    t0=$(date +%s)
    LOG_FILE="$log" "$RUNNER" -t "$test" -c "$cfg" -s "$seed" $compile_flag > "$OUT/.last_run" 2>&1
    rc=$?
    secs=$(( $(date +%s) - t0 ))
    total=$((total + 1))

    if [[ $rc -eq 2 ]]; then
      # Compile error: record every run of this config as failed and move on
      cat "$OUT/.last_run"
      for r in "${RUNS[@]}"; do
        read -r t s <<< "$r"
        echo "$cfg,$t,$s,COMPILE_ERROR,,,,," >> "$CSV"
      done
      failed=$((failed + ${#RUNS[@]})); total=$((total - 1 + ${#RUNS[@]}))
      FAILED_LIST+=("$cfg: compile error")
      break
    fi

    cycles=$(grep -oE "\(([0-9]+) cycles checked" "$log" 2>/dev/null | grep -oE "[0-9]+" | head -1)
    mism=$(grep -E "^\s+mismatches\s+:" "$log" 2>/dev/null | grep -oE "[0-9]+" | tail -1)
    sva=$(grep -E "^ Assertions: [0-9]+ failure" "$log" 2>/dev/null | grep -oE "[0-9]+" | head -1)
    cov=$(grep -E "tracker total \(fifo_cg bins\)" "$log" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | head -1)

    if [[ $rc -eq 0 ]]; then
      result="PASS"; passed=$((passed + 1))
    else
      result="FAIL"; failed=$((failed + 1)); FAILED_LIST+=("$cfg $test seed=$seed  ($log)")
    fi
    printf "  %-4s %-8s %-28s seed=%-3s cycles=%-6s cov=%6s%%  %3ss\n" \
      "$result" "$cfg" "$test" "$seed" "${cycles:--}" "${cov:--}" "$secs"
    echo "$cfg,$test,$seed,$result,${cycles:-},${mism:-},${sva:-},${cov:-},$secs" >> "$CSV"
  done
done
rm -f "$OUT/.last_run"

{
  echo "Regression summary"
  echo "  flow      : $FLOW"
  echo "  simulator : $SIM"
  echo "  date      : $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "  configs   : $CONFIGS"
  echo "  seeds     : random=[$SEEDS] stress=[$STRESS_SEEDS]"
  echo "  runs      : $total   passed: $passed   failed: $failed"
  echo
  printf "%-8s %-30s %-5s %-6s %-8s %-6s %-6s %-8s\n" config test seed result cycles mism sva cov%
  tail -n +2 "$CSV" | while IFS=, read -r c t s r cy m a cv sec; do
    printf "%-8s %-30s %-5s %-6s %-8s %-6s %-6s %-8s\n" "$c" "$t" "$s" "$r" "$cy" "$m" "$a" "$cv"
  done
  echo
  echo "Merged functional coverage per configuration"
  python3 "$ROOT/scripts/coverage_report.py" "$OUT" 2>&1
  if [[ ${#FAILED_LIST[@]} -gt 0 ]]; then
    echo
    echo "Failures:"
    printf '  %s\n' "${FAILED_LIST[@]}"
  fi
} > "$SUMMARY"

cp "$SUMMARY" "$RESULTS/regression/latest_${FLOW}_${SIM}.txt"
echo
cat "$SUMMARY" | sed -n '1,8p'
echo "  ... full table: $SUMMARY"

if [[ $failed -eq 0 && $total -gt 0 ]]; then
  info "REGRESSION PASSED ($passed/$total)"
  exit 0
else
  info "REGRESSION FAILED ($failed of $total runs failed)"
  exit 1
fi
