//------------------------------------------------------------------------------
// File        : fifo_assertions.sv
// Description : SVA properties for sync_fifo, attached with `bind` so the RTL
//               stays free of verification code. Shared by the SV and UVM
//               testbenches.
//
//   bind sync_fifo fifo_assertions #(...) u_fifo_sva (.*);
//
// With .* the ports connect by name to signals inside sync_fifo, including
// the internal state wr_ptr, rd_ptr and count (white-box checks). Acceptance
// is recomputed here from the pins (wr_en & ~full, rd_en & ~empty) rather
// than taken from the RTL's own wr_accept/rd_accept.
//
// Assertions check properties over time; the scoreboard checks data
// correctness against an independent model. Every failure increments
// sva_error_count, which the testbench top includes in the pass/fail verdict.
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module fifo_assertions #(
  parameter int DATA_WIDTH         = 8,
  parameter int DEPTH              = 16,
  parameter int ALMOST_FULL_LEVEL  = 14,
  parameter int ALMOST_EMPTY_LEVEL = 1
) (
  input logic                         clk,
  input logic                         rst_n,
  input logic                         wr_en,
  input logic                         rd_en,
  input logic [DATA_WIDTH-1:0]        data_in,
  input logic [DATA_WIDTH-1:0]        data_out,
  input logic                         full,
  input logic                         empty,
  input logic                         almost_full,
  input logic                         almost_empty,
  // Internal state of sync_fifo
  input logic [$clog2(DEPTH)-1:0]     wr_ptr,
  input logic [$clog2(DEPTH)-1:0]     rd_ptr,
  input logic [$clog2(DEPTH+1)-1:0]   count
);

  localparam int PTR_W = $clog2(DEPTH);
  localparam int CNT_W = $clog2(DEPTH + 1);

  localparam logic [PTR_W-1:0] PTR_LAST = PTR_W'(DEPTH - 1);
  localparam logic [CNT_W-1:0] CNT_FULL = CNT_W'(DEPTH);
  localparam logic [CNT_W-1:0] CNT_AF   = CNT_W'(ALMOST_FULL_LEVEL);
  localparam logic [CNT_W-1:0] CNT_AE   = CNT_W'(ALMOST_EMPTY_LEVEL);

  int unsigned sva_error_count = 0;

  logic wr_acc;
  logic rd_acc;
  assign wr_acc = wr_en && !full;
  assign rd_acc = rd_en && !empty;

  function automatic logic [PTR_W-1:0] ptr_inc(logic [PTR_W-1:0] p);
    return (p == PTR_LAST) ? '0 : p + 1'b1;
  endfunction

  //----------------------------------------------------------------------------
  // 1. full and empty are never asserted together
  //----------------------------------------------------------------------------
  a_full_empty_exclusive: assert property (
    @(posedge clk) disable iff (!rst_n) !(full && empty))
    else begin sva_error_count++; $error("[SVA] full and empty asserted together"); end

  //----------------------------------------------------------------------------
  // 2. Occupancy stays within 0..DEPTH
  //----------------------------------------------------------------------------
  a_count_in_range: assert property (
    @(posedge clk) disable iff (!rst_n) count <= CNT_FULL)
    else begin sva_error_count++; $error("[SVA] count=%0d exceeds DEPTH=%0d", count, DEPTH); end

  //----------------------------------------------------------------------------
  // 3. Read pointer moves only on an accepted read, by exactly one (with wrap)
  //----------------------------------------------------------------------------
  a_rd_ptr_hold: assert property (
    @(posedge clk) disable iff (!rst_n) !rd_acc |=> $stable(rd_ptr))
    else begin sva_error_count++; $error("[SVA] rd_ptr moved without an accepted read"); end

  a_rd_ptr_advance: assert property (
    @(posedge clk) disable iff (!rst_n) rd_acc |=> rd_ptr == ptr_inc($past(rd_ptr)))
    else begin sva_error_count++; $error("[SVA] rd_ptr did not advance correctly on an accepted read"); end

  //----------------------------------------------------------------------------
  // 4. Write pointer moves only on an accepted write, by exactly one (with wrap)
  //----------------------------------------------------------------------------
  a_wr_ptr_hold: assert property (
    @(posedge clk) disable iff (!rst_n) !wr_acc |=> $stable(wr_ptr))
    else begin sva_error_count++; $error("[SVA] wr_ptr moved without an accepted write"); end

  a_wr_ptr_advance: assert property (
    @(posedge clk) disable iff (!rst_n) wr_acc |=> wr_ptr == ptr_inc($past(wr_ptr)))
    else begin sva_error_count++; $error("[SVA] wr_ptr did not advance correctly on an accepted write"); end

  //----------------------------------------------------------------------------
  // 5. Reset clears pointers, occupancy and data_out (synchronous reset:
  //    checked on the edge after rst_n is sampled low)
  //----------------------------------------------------------------------------
  a_reset_clears: assert property (
    @(posedge clk) !rst_n |=> (wr_ptr == '0 && rd_ptr == '0 && count == '0 && data_out == '0))
    else begin sva_error_count++; $error("[SVA] reset did not clear pointers/count/data_out"); end

  //----------------------------------------------------------------------------
  // 6. Status flags agree with occupancy
  //----------------------------------------------------------------------------
  a_full_matches_count: assert property (
    @(posedge clk) disable iff (!rst_n) full == (count == CNT_FULL))
    else begin sva_error_count++; $error("[SVA] full=%0b but count=%0d", full, count); end

  a_empty_matches_count: assert property (
    @(posedge clk) disable iff (!rst_n) empty == (count == 0))
    else begin sva_error_count++; $error("[SVA] empty=%0b but count=%0d", empty, count); end

  a_almost_full_matches_count: assert property (
    @(posedge clk) disable iff (!rst_n) almost_full == (count >= CNT_AF))
    else begin sva_error_count++; $error("[SVA] almost_full=%0b but count=%0d", almost_full, count); end

  a_almost_empty_matches_count: assert property (
    @(posedge clk) disable iff (!rst_n) almost_empty == (count <= CNT_AE))
    else begin sva_error_count++; $error("[SVA] almost_empty=%0b but count=%0d", almost_empty, count); end

  //----------------------------------------------------------------------------
  // 7. data_out changes only on an accepted read (or reset)
  //----------------------------------------------------------------------------
  a_data_out_hold: assert property (
    @(posedge clk) disable iff (!rst_n) !rd_acc |=> $stable(data_out))
    else begin sva_error_count++; $error("[SVA] data_out changed without an accepted read"); end

  //----------------------------------------------------------------------------
  // Additional checks
  //----------------------------------------------------------------------------
  // Occupancy update rule, including simultaneous read+write
  a_count_inc: assert property (
    @(posedge clk) disable iff (!rst_n) (wr_acc && !rd_acc) |=> count == $past(count) + 1'b1)
    else begin sva_error_count++; $error("[SVA] count did not increment on write-only"); end

  a_count_dec: assert property (
    @(posedge clk) disable iff (!rst_n) (rd_acc && !wr_acc) |=> count == $past(count) - 1'b1)
    else begin sva_error_count++; $error("[SVA] count did not decrement on read-only"); end

  a_count_hold: assert property (
    @(posedge clk) disable iff (!rst_n) (wr_acc == rd_acc) |=> $stable(count))
    else begin sva_error_count++; $error("[SVA] count changed on both/neither accepted"); end

  // No X/Z on outputs or control inputs once out of reset
  a_outputs_known: assert property (
    @(posedge clk) disable iff (!rst_n)
      !$isunknown({data_out, full, empty, almost_full, almost_empty}))
    else begin sva_error_count++; $error("[SVA] X/Z on a FIFO output"); end

  a_controls_known: assert property (
    @(posedge clk) disable iff (!rst_n) !$isunknown({wr_en, rd_en}))
    else begin sva_error_count++; $error("[SVA] X/Z on wr_en/rd_en"); end

  a_write_data_known: assert property (
    @(posedge clk) disable iff (!rst_n) wr_en |-> !$isunknown(data_in))
    else begin sva_error_count++; $error("[SVA] X/Z on data_in during a write request"); end

  //----------------------------------------------------------------------------
  // Cover properties: evidence that the interesting corners were exercised.
  // Each condition is named once and used twice: by a cover property (for
  // the simulator's coverage database) and by a hit counter printed in the
  // log (cover-property action blocks are not supported by every simulator).
  //----------------------------------------------------------------------------
  logic cv_write_while_full, cv_read_while_empty, cv_both_while_full,
        cv_both_while_empty, cv_both_accepted, cv_wr_ptr_wrap, cv_rd_ptr_wrap,
        cv_reset_while_full, cv_reset_while_partial;

  assign cv_write_while_full    = rst_n && full  && wr_en && !rd_en;
  assign cv_read_while_empty    = rst_n && empty && rd_en && !wr_en;
  assign cv_both_while_full     = rst_n && full  && wr_en && rd_en;
  assign cv_both_while_empty    = rst_n && empty && wr_en && rd_en;
  assign cv_both_accepted       = rst_n && wr_acc && rd_acc;
  assign cv_wr_ptr_wrap         = rst_n && wr_acc && (wr_ptr == PTR_LAST);
  assign cv_rd_ptr_wrap         = rst_n && rd_acc && (rd_ptr == PTR_LAST);
  assign cv_reset_while_full    = !rst_n && full;
  assign cv_reset_while_partial = !rst_n && !full && !empty;

  c_write_while_full:    cover property (@(posedge clk) cv_write_while_full);
  c_read_while_empty:    cover property (@(posedge clk) cv_read_while_empty);
  c_both_while_full:     cover property (@(posedge clk) cv_both_while_full);
  c_both_while_empty:    cover property (@(posedge clk) cv_both_while_empty);
  c_both_accepted:       cover property (@(posedge clk) cv_both_accepted);
  c_wr_ptr_wrap:         cover property (@(posedge clk) cv_wr_ptr_wrap);
  c_rd_ptr_wrap:         cover property (@(posedge clk) cv_rd_ptr_wrap);
  c_reset_while_full:    cover property (@(posedge clk) cv_reset_while_full);
  c_reset_while_partial: cover property (@(posedge clk) cv_reset_while_partial);

  int unsigned n_write_while_full, n_read_while_empty, n_both_while_full,
               n_both_while_empty, n_both_accepted, n_wr_ptr_wrap,
               n_rd_ptr_wrap, n_reset_while_full, n_reset_while_partial;

  always @(posedge clk) begin : cover_hit_counters
    if (cv_write_while_full)    n_write_while_full++;
    if (cv_read_while_empty)    n_read_while_empty++;
    if (cv_both_while_full)     n_both_while_full++;
    if (cv_both_while_empty)    n_both_while_empty++;
    if (cv_both_accepted)       n_both_accepted++;
    if (cv_wr_ptr_wrap)         n_wr_ptr_wrap++;
    if (cv_rd_ptr_wrap)         n_rd_ptr_wrap++;
    if (cv_reset_while_full)    n_reset_while_full++;
    if (cv_reset_while_partial) n_reset_while_partial++;
  end

  function void report();
    $display("---------------------------------------------------------------");
    $display(" Assertions: %0d failure(s)", sva_error_count);
    $display(" Cover properties (hits):");
    $display("   c_write_while_full    %0d", n_write_while_full);
    $display("   c_read_while_empty    %0d", n_read_while_empty);
    $display("   c_both_while_full     %0d", n_both_while_full);
    $display("   c_both_while_empty    %0d", n_both_while_empty);
    $display("   c_both_accepted       %0d", n_both_accepted);
    $display("   c_wr_ptr_wrap         %0d", n_wr_ptr_wrap);
    $display("   c_rd_ptr_wrap         %0d", n_rd_ptr_wrap);
    $display("   c_reset_while_full    %0d", n_reset_while_full);
    $display("   c_reset_while_partial %0d", n_reset_while_partial);
  endfunction

endmodule : fifo_assertions
