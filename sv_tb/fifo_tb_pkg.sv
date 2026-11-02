//------------------------------------------------------------------------------
// File        : fifo_tb_pkg.sv
// Description : Package for the class-based (non-UVM) FIFO testbench.
//
// The DUT configuration is chosen at compile time with +define+ (see
// scripts/run_sv.sh). tb_top passes the same values to the DUT as parameter
// overrides, so a single RTL file is verified in every configuration.
//
//   +define+FIFO_DATA_WIDTH=<n>   default 8
//   +define+FIFO_DEPTH=<n>        default 16  (testbench needs >= 4)
//   +define+FIFO_AF_LEVEL=<n>     default DEPTH-2  (14 for DEPTH=16)
//   +define+FIFO_AE_LEVEL=<n>     default 1
//
// The class files below are `included here; compile only this package file,
// not the individual class files.
//------------------------------------------------------------------------------
`timescale 1ns/1ps

`ifndef FIFO_DATA_WIDTH
  `define FIFO_DATA_WIDTH 8
`endif
`ifndef FIFO_DEPTH
  `define FIFO_DEPTH 16
`endif

package fifo_tb_pkg;

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

  // Note: classes declare "virtual fifo_if #(DATA_WIDTH)" directly instead of
  // through a typedef. Verilator 5.048 does not sample clocking-block inputs
  // accessed through a typedef'd virtual interface; the explicit form works
  // on every simulator.

  localparam data_t DATA_MAX = '1;

  // Occupancy coverage bins: empty | low | middle | high | full
  localparam int unsigned OCC_LOW_MAX  = (DEPTH / 4 > 0) ? DEPTH / 4 : 1;
  localparam int unsigned OCC_HIGH_MIN = DEPTH - OCC_LOW_MAX;

  //----------------------------------------------------------------------------
  // Testbench components
  //----------------------------------------------------------------------------
  `include "fifo_transaction.sv"
  `include "fifo_generator.sv"
  `include "fifo_driver.sv"
  `include "fifo_monitor.sv"
  `include "fifo_scoreboard.sv"
  `include "fifo_coverage.sv"
  `include "fifo_environment.sv"
  `include "fifo_test.sv"

endpackage : fifo_tb_pkg
