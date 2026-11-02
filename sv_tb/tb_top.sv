//------------------------------------------------------------------------------
// File        : tb_top.sv
// Description : Simulation top for the class-based testbench.
//
//   * Generates the clock, instantiates the interface and the DUT (with the
//     configuration from fifo_tb_pkg passed as parameter overrides) and binds
//     the SVA module into the DUT.
//   * Builds the test selected with +TESTNAME=<name> and runs it.
//   * Final verdict = scoreboard mismatches + directed-test check failures +
//     assertion failures. A failing test ends with $fatal so the simulator
//     exits with a non-zero status; a passing one prints "TEST PASSED".
//
// Run-time options: +TESTNAME=<name>  +NUM_TXN=<n>  +VERBOSITY=<n>
//                   +MAX_ERRORS=<n>   +TIMEOUT_NS=<n>  +DUMP (VCD waveform)
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

  import fifo_tb_pkg::*;

  localparam time CLK_PERIOD = 10ns;

  // Testbench constraint: the occupancy coverage bins need DEPTH >= 4
  if (DEPTH < 4) begin : g_tb_depth_check
    $error("tb_top: the testbench needs DEPTH >= 4 (got %0d)", DEPTH);
  end

  //----------------------------------------------------------------------------
  // Clock, interface, DUT
  //----------------------------------------------------------------------------
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

  // Parameter expressions in a bind resolve in the target (sync_fifo) scope
  bind sync_fifo fifo_assertions #(
    .DATA_WIDTH         (DATA_WIDTH),
    .DEPTH              (DEPTH),
    .ALMOST_FULL_LEVEL  (ALMOST_FULL_LEVEL),
    .ALMOST_EMPTY_LEVEL (ALMOST_EMPTY_LEVEL)
  ) u_fifo_sva (.*);

  //----------------------------------------------------------------------------
  // Test execution
  //----------------------------------------------------------------------------
  initial begin
    fifo_base_test test;
    string         test_name;
    int unsigned   sva_errors;

    if ($test$plusargs("DUMP")) begin
      $dumpfile("waves.vcd");
      $dumpvars(0, tb_top);
    end

    if (!$value$plusargs("TESTNAME=%s", test_name)) test_name = "random_balanced_test";

    test = fifo_test_factory::create(test_name, fifo_vif);
    test.run();

    dut.u_fifo_sva.report();
    sva_errors = dut.u_fifo_sva.sva_error_count;

    $display("===============================================================");
    if (test.passed() && sva_errors == 0) begin
      $display("TEST PASSED: %s (%0d cycles checked, 0 mismatches, 0 assertion failures)",
               test_name, test.env.scb.num_checked);
      $display("===============================================================");
      $finish;
    end else begin
      $display("TEST FAILED: %s (scoreboard mismatches=%0d, check failures=%0d, assertion failures=%0d)",
               test_name, test.env.scb.num_errors, test.check_errors, sva_errors);
      $display("===============================================================");
      $fatal(1, "TEST FAILED: %s", test_name);
    end
  end

  // Watchdog: a hung test must fail, not run forever
  initial begin
    longint unsigned timeout_ns;
    timeout_ns = 50_000_000;
    void'($value$plusargs("TIMEOUT_NS=%d", timeout_ns));
    #(timeout_ns);   // time unit is 1ns
    $fatal(1, "TEST FAILED: watchdog timeout after %0d ns", timeout_ns);
  end

endmodule : tb_top
