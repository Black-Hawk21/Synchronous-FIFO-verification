#!/usr/bin/env bash
#------------------------------------------------------------------------------
# run_sv.sh - compile and run one test of the class-based SystemVerilog TB
#
# Usage: scripts/run_sv.sh [options]
#   -t, --test NAME      test to run                 (default: random_balanced_test)
#   -c, --config NAME    small|default|wide|deep|npot (default: default)
#   -s, --seed N         random seed                 (default: 1)
#   -n, --num-txn N      transactions for random/stress tests
#   -v, --verbosity N    scoreboard verbosity 0|1|2
#       --sim NAME       verilator|questa|vcs|xcelium (default: $SIM or verilator)
#       --no-compile     reuse the existing build for this config
#       --dump           write waves.vcd next to the log
#       --list           list the available tests
#   -h, --help
#
# Logs:   results/logs/sv/<sim>/<config>/<test>__seed<N>.log
# Exit:   0 = TEST PASSED, 1 = test failed, 2 = usage or compile error
#------------------------------------------------------------------------------
set -u
source "$(dirname "$0")/common.sh"

TEST="random_balanced_test"
CONFIG="default"
SEED=1
NUM_TXN=""
VERBOSITY=""
COMPILE=1
DUMP=0

usage() { sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--test)      TEST="$2"; shift 2 ;;
    -c|--config)    CONFIG="$2"; shift 2 ;;
    -s|--seed)      SEED="$2"; shift 2 ;;
    -n|--num-txn)   NUM_TXN="$2"; shift 2 ;;
    -v|--verbosity) VERBOSITY="$2"; shift 2 ;;
    --sim)          SIM="$2"; shift 2 ;;
    --no-compile)   COMPILE=0; shift ;;
    --dump)         DUMP=1; shift ;;
    --list)         echo "directed: $SV_DIRECTED_TESTS"; echo "random:   $SV_RANDOM_TESTS"
                    echo "stress:   $SV_STRESS_TESTS"; exit 0 ;;
    -h|--help)      usage 0 ;;
    *) echo "Unknown option '$1'" >&2; usage 2 ;;
  esac
done

DEFINES="$(config_defines "$CONFIG")" || exit 2
BUILD="${BUILD_DIR:-$RESULTS/build/sv/$SIM/$CONFIG}"
LOG="${LOG_FILE:-$RESULTS/logs/sv/$SIM/$CONFIG/${TEST}__seed${SEED}.log}"

FILES=(
  "$RTL_FILE"
  "$ROOT/sv_tb/fifo_interface.sv"
  "$ROOT/sv_tb/fifo_tb_pkg.sv"
  "$ROOT/sv_tb/fifo_assertions.sv"
  "$ROOT/sv_tb/tb_top.sv"
)

if [[ $COMPILE -eq 1 ]]; then
  info "Compiling SV testbench: config=$CONFIG ($(config_desc "$CONFIG")) sim=$SIM"
  compile_tb "$BUILD" tb_top "$DEFINES" "+incdir+$ROOT/sv_tb" "${FILES[@]}" || exit 2
fi

PLUSARGS=("+TESTNAME=$TEST")
[[ -n "$NUM_TXN"   ]] && PLUSARGS+=("+NUM_TXN=$NUM_TXN")
[[ -n "$VERBOSITY" ]] && PLUSARGS+=("+VERBOSITY=$VERBOSITY")
[[ $DUMP -eq 1     ]] && PLUSARGS+=("+DUMP")

info "Running $TEST (config=$CONFIG seed=$SEED)"
run_sim "$BUILD" tb_top "$LOG" "$SEED" "${PLUSARGS[@]}"
STATUS=$?

if log_passed "$LOG" "$STATUS"; then
  info "PASS  $TEST  config=$CONFIG seed=$SEED  ($LOG)"
  exit 0
else
  info "FAIL  $TEST  config=$CONFIG seed=$SEED  ($LOG)"
  grep -E "\[FAIL\]|\[SVA\]|\[CHECK\].*expected|TEST FAILED|Fatal|%Error" "$LOG" | head -10
  exit 1
fi
