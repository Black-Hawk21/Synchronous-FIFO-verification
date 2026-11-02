#!/usr/bin/env bash
#------------------------------------------------------------------------------
# common.sh - shared helpers for the run/regression scripts (source, don't run)
#------------------------------------------------------------------------------

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS="${RESULTS:-$ROOT/results}"

# Simulator: verilator | questa | vcs | xcelium   (override with SIM=... or --sim)
SIM="${SIM:-verilator}"
VERILATOR="${VERILATOR:-verilator}"

# RTL under test (the mutation script points this at mutated copies)
RTL_FILE="${RTL_FILE:-$ROOT/rtl/sync_fifo.sv}"

# Optional extra simulator flags, e.g. EXTRA_RUN_ARGS="-coverage"
EXTRA_COMPILE_ARGS="${EXTRA_COMPILE_ARGS:-}"
EXTRA_RUN_ARGS="${EXTRA_RUN_ARGS:-}"

ALL_CONFIGS="small default wide deep npot"

#------------------------------------------------------------------------------
# Parameter configurations (verification plan, section 3.3)
#   name     DATA_WIDTH  DEPTH   (ALMOST_FULL_LEVEL = DEPTH-2, ALMOST_EMPTY_LEVEL = 1)
#------------------------------------------------------------------------------
config_defines() {
  local w d
  case "$1" in
    small)   w=8;  d=4  ;;
    default) w=8;  d=16 ;;
    wide)    w=32; d=16 ;;
    deep)    w=8;  d=64 ;;
    npot)    w=8;  d=10 ;;
    *) echo "Unknown config '$1' (use: $ALL_CONFIGS)" >&2; return 1 ;;
  esac
  echo "+define+FIFO_DATA_WIDTH=$w +define+FIFO_DEPTH=$d"
}

config_desc() {
  case "$1" in
    small)   echo "W=8  D=4"  ;;
    default) echo "W=8  D=16" ;;
    wide)    echo "W=32 D=16" ;;
    deep)    echo "W=8  D=64" ;;
    npot)    echo "W=8  D=10" ;;
  esac
}

SV_DIRECTED_TESTS="reset_test basic_write_test basic_read_test fill_test empty_test overflow_test underflow_test simultaneous_rw_test pointer_wrap_test reset_mid_operation_test"
SV_RANDOM_TESTS="random_balanced_test random_write_heavy_test random_read_heavy_test"
SV_STRESS_TESTS="stress_test"

UVM_DIRECTED_TESTS="fifo_basic_test fifo_reset_test fifo_fill_test fifo_empty_test fifo_overflow_test fifo_underflow_test fifo_simultaneous_rw_test fifo_pointer_wrap_test fifo_reset_mid_operation_test"
UVM_RANDOM_TESTS="fifo_random_test fifo_random_write_heavy_test fifo_random_read_heavy_test"
UVM_STRESS_TESTS="fifo_stress_test"

#------------------------------------------------------------------------------
# Logging helpers
#------------------------------------------------------------------------------
die()  { echo "ERROR: $*" >&2; exit 2; }
info() { echo "[$(date +%H:%M:%S)] $*"; }

# A run passes only if the log has the PASS banner, has no FAIL banner and
# the simulator exited with status 0.
log_passed() {
  local log="$1" status="$2"
  [[ "$status" -eq 0 ]] || return 1
  grep -q "^TEST PASSED" "$log" || return 1
  ! grep -q "TEST FAILED" "$log"
}

#------------------------------------------------------------------------------
# Seed plusarg per simulator
#------------------------------------------------------------------------------
seed_args() {
  case "$SIM" in
    verilator) echo "+verilator+seed+$1 +verilator+error+limit+1000" ;;
    questa)    echo "-sv_seed $1" ;;
    vcs)       echo "+ntb_random_seed=$1" ;;
    xcelium)   echo "-svseed $1" ;;
  esac
}

#------------------------------------------------------------------------------
# compile_tb <build_dir> <top> <defines> <incdirs> <files...>
#   Extra simulator-specific compile flags may be passed in EXTRA_COMPILE_ARGS.
#------------------------------------------------------------------------------
compile_tb() {
  local build="$1" top="$2" defines="$3" incdirs="$4"; shift 4
  local files=("$@")
  mkdir -p "$build"
  local clog="$build/compile.log"
  case "$SIM" in
    verilator)
      # shellcheck disable=SC2086
      "$VERILATOR" --binary --timing --assert -j 0 --timescale 1ns/1ps \
        -Wno-fatal -Wno-COVERIGN -Wno-ZERODLY \
        --top-module "$top" --Mdir "$build/obj" -o sim \
        $defines $incdirs $EXTRA_COMPILE_ARGS "${files[@]}" > "$clog" 2>&1
      ;;
    questa)
      rm -rf "$build/work"
      { vlib "$build/work" &&
        # shellcheck disable=SC2086
        vlog -sv -work "$build/work" -timescale 1ns/1ps $defines $incdirs \
             $EXTRA_COMPILE_ARGS "${files[@]}"; } > "$clog" 2>&1
      ;;
    vcs)
      # shellcheck disable=SC2086
      ( cd "$build" && vcs -full64 -sverilog -timescale=1ns/1ps -assert svaext \
          $defines $incdirs $EXTRA_COMPILE_ARGS "${files[@]}" \
          -top "$top" -o "$build/simv" ) > "$clog" 2>&1
      ;;
    xcelium)
      # shellcheck disable=SC2086
      xrun -64bit -sv -timescale 1ns/1ps -elaborate -access +r \
        -xmlibdirpath "$build" $defines $incdirs $EXTRA_COMPILE_ARGS \
        "${files[@]}" -top "$top" > "$clog" 2>&1
      ;;
    *) die "Unsupported simulator '$SIM' (verilator|questa|vcs|xcelium)" ;;
  esac
  local status=$?
  if [[ $status -ne 0 ]] || grep -qE "^%Error|^\*\* Error|^Error-|\*E," "$clog"; then
    echo "Compilation failed - see $clog" >&2
    grep -E "^%Error|^\*\* Error|^Error-|\*E," "$clog" | head -20 >&2
    return 1
  fi
  return 0
}

#------------------------------------------------------------------------------
# run_sim <build_dir> <top> <log> <seed> <plusargs...>
#   Extra simulator-specific run flags may be passed in EXTRA_RUN_ARGS.
#------------------------------------------------------------------------------
run_sim() {
  local build="$1" top="$2" log="$3" seed="$4"; shift 4
  local plusargs=("$@")
  mkdir -p "$(dirname "$log")"
  local rundir; rundir="$(dirname "$log")"
  # shellcheck disable=SC2046,SC2086
  case "$SIM" in
    verilator)
      ( cd "$rundir" && "$build/obj/sim" $(seed_args "$seed") $EXTRA_RUN_ARGS "${plusargs[@]}" ) > "$log" 2>&1 ;;
    questa)
      ( cd "$rundir" && vsim -c -work "$build/work" $(seed_args "$seed") $EXTRA_RUN_ARGS "$top" "${plusargs[@]}" \
          -do "run -all; quit -f" ) > "$log" 2>&1 ;;
    vcs)
      ( cd "$rundir" && "$build/simv" $(seed_args "$seed") $EXTRA_RUN_ARGS "${plusargs[@]}" ) > "$log" 2>&1 ;;
    xcelium)
      ( cd "$rundir" && xrun -64bit -R -xmlibdirpath "$build" $(seed_args "$seed") $EXTRA_RUN_ARGS "${plusargs[@]}" ) > "$log" 2>&1 ;;
  esac
}
