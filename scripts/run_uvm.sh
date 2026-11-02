#!/usr/bin/env bash
#------------------------------------------------------------------------------
# run_uvm.sh - compile and run one test of the UVM testbench
#
# Usage: scripts/run_uvm.sh [options]
#   -t, --test NAME      UVM test (+UVM_TESTNAME)      (default: fifo_basic_test)
#   -c, --config NAME    small|default|wide|deep|npot  (default: default)
#   -s, --seed N         random seed                   (default: 1)
#   -n, --num-txn N      items for random/stress tests
#   -v, --verbosity V    UVM verbosity: UVM_LOW|UVM_MEDIUM|UVM_HIGH|UVM_DEBUG
#       --sim NAME       verilator|questa|vcs|xcelium  (default: $SIM or verilator)
#       --no-compile     reuse the existing build for this config
#       --dump           write waves.vcd next to the log
#       --list           list the available tests
#   -h, --help
#
# UVM library:
#   UVM_HOME=<dir>  Accellera UVM source tree (the directory that contains
#                   src/uvm_pkg.sv), compiled with +define+UVM_NO_DPI.
#                   Required for verilator; optional for the others.
#   Without UVM_HOME: questa uses $QUESTA_HOME/verilog_src/uvm-1.2,
#                     vcs uses -ntb_opts uvm-1.2, xcelium uses -uvm.
#
# Logs:   results/logs/uvm/<sim>/<config>/<test>__seed<N>.log
# Exit:   0 = TEST PASSED, 1 = test failed, 2 = usage or compile error
#------------------------------------------------------------------------------
set -u
source "$(dirname "$0")/common.sh"

TEST="fifo_basic_test"
CONFIG="default"
SEED=1
NUM_TXN=""
VERBOSITY=""
COMPILE=1
DUMP=0

usage() { sed -n '3,27p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

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
    --list)         echo "directed: $UVM_DIRECTED_TESTS"; echo "random:   $UVM_RANDOM_TESTS"
                    echo "stress:   $UVM_STRESS_TESTS"; exit 0 ;;
    -h|--help)      usage 0 ;;
    *) echo "Unknown option '$1'" >&2; usage 2 ;;
  esac
done

DEFINES="$(config_defines "$CONFIG")" || exit 2
BUILD="${BUILD_DIR:-$RESULTS/build/uvm/$SIM/$CONFIG}"
LOG="${LOG_FILE:-$RESULTS/logs/uvm/$SIM/$CONFIG/${TEST}__seed${SEED}.log}"
INCDIRS="+incdir+$ROOT/uvm_tb"
UVM_FILES=()

# Select the UVM library
UVM_HOME="${UVM_HOME:-}"
if [[ -z "$UVM_HOME" && "$SIM" == "questa" ]]; then
  for q in "${QUESTA_HOME:-}" "${MTI_HOME:-}"; do
    [[ -n "$q" && -f "$q/verilog_src/uvm-1.2/src/uvm_pkg.sv" ]] && UVM_HOME="$q/verilog_src/uvm-1.2" && break
  done
fi
if [[ -n "$UVM_HOME" ]]; then
  [[ -f "$UVM_HOME/src/uvm_pkg.sv" ]] || die "UVM_HOME=$UVM_HOME does not contain src/uvm_pkg.sv"
  INCDIRS="$INCDIRS +incdir+$UVM_HOME/src"
  DEFINES="$DEFINES +define+UVM_NO_DPI"
  UVM_FILES=("$UVM_HOME/src/uvm_pkg.sv")
  case "$SIM" in
    xcelium) EXTRA_COMPILE_ARGS="$EXTRA_COMPILE_ARGS -uvmnocdnsextra" ;;
    verilator) EXTRA_COMPILE_ARGS="$EXTRA_COMPILE_ARGS -Wno-lint -Wno-style -Wno-CONSTRAINTIGN -Wno-MISINDENT" ;;
  esac
else
  case "$SIM" in
    vcs)       EXTRA_COMPILE_ARGS="$EXTRA_COMPILE_ARGS -ntb_opts uvm-1.2" ;;
    xcelium)   EXTRA_COMPILE_ARGS="$EXTRA_COMPILE_ARGS -uvm" ;;
    verilator) die "Verilator needs the Accellera UVM sources: set UVM_HOME (see README)" ;;
    questa)    die "UVM library not found: set UVM_HOME or QUESTA_HOME" ;;
  esac
fi

FILES=(
  "$RTL_FILE"
  "$ROOT/uvm_tb/fifo_if.sv"
  "${UVM_FILES[@]}"
  "$ROOT/uvm_tb/fifo_pkg.sv"
  "$ROOT/sv_tb/fifo_assertions.sv"
  "$ROOT/uvm_tb/tb_top.sv"
)

if [[ $COMPILE -eq 1 ]]; then
  info "Compiling UVM testbench: config=$CONFIG ($(config_desc "$CONFIG")) sim=$SIM"
  compile_tb "$BUILD" tb_top "$DEFINES" "$INCDIRS" "${FILES[@]}" || exit 2
fi

PLUSARGS=("+UVM_TESTNAME=$TEST" "+UVM_NO_RELNOTES")
[[ -n "$NUM_TXN"   ]] && PLUSARGS+=("+NUM_TXN=$NUM_TXN")
[[ -n "$VERBOSITY" ]] && PLUSARGS+=("+UVM_VERBOSITY=$VERBOSITY")
[[ $DUMP -eq 1     ]] && PLUSARGS+=("+DUMP")

info "Running $TEST (config=$CONFIG seed=$SEED)"
run_sim "$BUILD" tb_top "$LOG" "$SEED" "${PLUSARGS[@]}"
STATUS=$?

if log_passed "$LOG" "$STATUS"; then
  info "PASS  $TEST  config=$CONFIG seed=$SEED  ($LOG)"
  exit 0
else
  info "FAIL  $TEST  config=$CONFIG seed=$SEED  ($LOG)"
  grep -E "\[FAIL\]|\[SVA\]|\[CHECK\].*expected|TEST FAILED|UVM_FATAL|UVM_ERROR @|%Error" "$LOG" | head -10
  exit 1
fi
