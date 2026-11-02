//------------------------------------------------------------------------------
// File        : tb_top.sv
// Description : Simulation top for the UVM testbench.
//
//   * Clock, interface and DUT (same RTL, configuration from fifo_pkg).
//   * Binds the shared SVA module (sv_tb/fifo_assertions.sv) into the DUT.
//   * Publishes the virtual interface through uvm_config_db and starts the
//     test named by +UVM_TESTNAME (default fifo_basic_test).
//   * Forwards assertion failures to the UVM report server so they are
//     counted like any other UVM_ERROR and fail the test.
//------------------------------------------------------------------------------
`timescale 1ns/1ps

`include "uvm_macros.svh"

module tb_top;

  import uvm_pkg::*;
  import fifo_pkg::*;

  localparam time CLK_PERIOD = 10ns;

  if (DEPTH < 4) begin : g_tb_depth_check
    $error("tb_top: the testbench needs DEPTH >= 4 (got %0d)", DEPTH);
  end

  logic clk;
  initial clk = 1'b0;
  always #(CLK_PERIOD / 2) clk = ~clk;

  fifo_if #(.DATA_WIDTH(DATA_WIDTH)) fifo_vif (.clk(clk));

  sync_fifo #(
    .DATA_WIDTH         (DATA_WIDTH),
    .DEPTH              (DEPTH),
    .ALMOST_FULL_LEVEL  (ALMOST_FULL_LEVEL),
    .ALMOST_EMPTY_LEVEL (ALMOST_EMPTY_LEVEL)
  ) dut (
    .clk          (clk),
    .rst_n        (fifo_vif.rst_n),
    .wr_en        (fifo_vif.wr_en),
    .rd_en        (fifo_vif.rd_en),
    .data_in      (fifo_vif.data_in),
    .data_out     (fifo_vif.data_out),
    .full         (fifo_vif.full),
    .empty        (fifo_vif.empty),
    .almost_full  (fifo_vif.almost_full),
    .almost_empty (fifo_vif.almost_empty)
  );

  bind sync_fifo fifo_assertions #(
    .DATA_WIDTH         (DATA_WIDTH),
    .DEPTH              (DEPTH),
    .ALMOST_FULL_LEVEL  (ALMOST_FULL_LEVEL),
    .ALMOST_EMPTY_LEVEL (ALMOST_EMPTY_LEVEL)
  ) u_fifo_sva (.*);

  initial begin
    uvm_config_db #(virtual fifo_if #(DATA_WIDTH))::set(null, "uvm_test_top*", "vif", fifo_vif);
    if ($test$plusargs("DUMP")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top);
    end
    run_test("fifo_basic_test");
  end

  // Every new assertion failure becomes a UVM_ERROR
  int unsigned sva_reported = 0;
  always @(posedge clk) begin
    if (dut.u_fifo_sva.sva_error_count != sva_reported) begin
      sva_reported = dut.u_fifo_sva.sva_error_count;
      `uvm_error("SVA", $sformatf("assertion failure count is now %0d (see [SVA] messages)",
                                  sva_reported))
    end
  end

  final dut.u_fifo_sva.report();

endmodule : tb_top
