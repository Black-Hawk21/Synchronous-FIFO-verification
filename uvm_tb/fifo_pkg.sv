//------------------------------------------------------------------------------
// File        : fifo_pkg.sv
// Description : UVM package for the FIFO testbench.
//
// DUT configuration is selected at compile time, exactly as in the SV flow:
//   +define+FIFO_DATA_WIDTH=<n>  (default 8)
//   +define+FIFO_DEPTH=<n>       (default 16, testbench needs >= 4)
//   +define+FIFO_AF_LEVEL=<n>    (default DEPTH-2)
//   +define+FIFO_AE_LEVEL=<n>    (default 1)
//
// All class files are `included here; compile only this package file.
//------------------------------------------------------------------------------
`timescale 1ns/1ps

`include "uvm_macros.svh"

`ifndef FIFO_DATA_WIDTH
  `define FIFO_DATA_WIDTH 8
`endif
`ifndef FIFO_DEPTH
  `define FIFO_DEPTH 16
`endif

package fifo_pkg;

  import uvm_pkg::*;

  //----------------------------------------------------------------------------
  // DUT configuration
  //----------------------------------------------------------------------------
  localparam int unsigned DATA_WIDTH = `FIFO_DATA_WIDTH;
  localparam int unsigned DEPTH      = `FIFO_DEPTH;

`ifdef FIFO_AF_LEVEL
  localparam int unsigned ALMOST_FULL_LEVEL = `FIFO_AF_LEVEL;
`else
  localparam int unsigned ALMOST_FULL_LEVEL = (DEPTH > 2) ? DEPTH - 2 : DEPTH;
`endif

`ifdef FIFO_AE_LEVEL
  localparam int unsigned ALMOST_EMPTY_LEVEL = `FIFO_AE_LEVEL;
`else
  localparam int unsigned ALMOST_EMPTY_LEVEL = 1;
`endif

  //----------------------------------------------------------------------------
  // Common types and constants
  //----------------------------------------------------------------------------
  typedef bit [DATA_WIDTH-1:0] data_t;

  // Components declare "virtual fifo_if #(DATA_WIDTH)" explicitly rather than
  // through a typedef (Verilator 5.048 does not sample clocking-block inputs
  // through a typedef'd virtual interface; the explicit form is portable).

  localparam data_t DATA_MAX = '1;

  // Occupancy coverage bins: empty | low | middle | high | full
  localparam int unsigned OCC_LOW_MAX  = (DEPTH / 4 > 0) ? DEPTH / 4 : 1;
  localparam int unsigned OCC_HIGH_MIN = DEPTH - OCC_LOW_MAX;

  //----------------------------------------------------------------------------
  // Agent
  //----------------------------------------------------------------------------
  `include "agents/fifo_sequence_item.sv"
  `include "agents/fifo_sequencer.sv"
  `include "agents/fifo_driver.sv"
  `include "agents/fifo_monitor.sv"
  `include "agents/fifo_agent.sv"

  //----------------------------------------------------------------------------
  // Environment
  //----------------------------------------------------------------------------
  `include "env/fifo_scoreboard.sv"
  `include "env/fifo_coverage.sv"
  `include "env/fifo_env.sv"

  //----------------------------------------------------------------------------
  // Sequences
  //----------------------------------------------------------------------------
  `include "sequences/fifo_base_sequence.sv"
  `include "sequences/fifo_reset_sequence.sv"
  `include "sequences/fifo_idle_sequence.sv"
  `include "sequences/fifo_write_sequence.sv"
  `include "sequences/fifo_read_sequence.sv"
  `include "sequences/fifo_rw_sequence.sv"
  `include "sequences/fifo_random_sequence.sv"
  `include "sequences/fifo_stress_sequence.sv"

  //----------------------------------------------------------------------------
  // Tests
  //----------------------------------------------------------------------------
  `include "tests/fifo_base_test.sv"
  `include "tests/fifo_basic_test.sv"
  `include "tests/fifo_directed_tests.sv"
  `include "tests/fifo_random_test.sv"

endpackage : fifo_pkg
