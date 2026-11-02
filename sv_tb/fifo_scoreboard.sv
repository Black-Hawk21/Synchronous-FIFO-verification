//------------------------------------------------------------------------------
// File        : fifo_scoreboard.sv
// Description : Checks every observed cycle against an independent reference
//               model.
//
// The model is a SystemVerilog queue plus the expected value of the
// registered output. It deliberately shares nothing with the RTL: no
// pointers, no counter, and it never looks at the DUT's full/empty flags to
// decide what should happen (that would be a common-mode error). Acceptance
// is derived from the model's own occupancy before the edge:
//
//     write accepted  <=>  wr_en && model occupancy <  DEPTH
//     read  accepted  <=>  rd_en && model occupancy >  0
//
// A read pops the oldest entry into expected_data_out; a write appends.
// Every cycle (including idle and rejected requests) data_out and all four
// flags are compared, which also proves that data_out holds its value when
// no read is accepted.
//------------------------------------------------------------------------------
`ifndef FIFO_SCOREBOARD_SV
`define FIFO_SCOREBOARD_SV

class fifo_scoreboard;

  mailbox #(fifo_transaction) mon2scb;

  // Reference model
  data_t expected_queue[$];
  data_t expected_data_out = '0;

  // Reporting controls
  int unsigned verbosity  = 1;    // 0: failures + summary
                                  // 1: + PASS line per accepted/ignored request
                                  // 2: + PASS line for idle cycles
  int unsigned max_errors = 10;   // stop the simulation at this many mismatches

  // Statistics
  int unsigned num_checked;
  int unsigned num_errors;
  int unsigned num_writes;
  int unsigned num_reads;
  int unsigned num_simultaneous;
  int unsigned num_ignored_writes;
  int unsigned num_ignored_reads;
  int unsigned num_resets;
  int unsigned max_occupancy;

  fifo_transaction last_tr;       // most recent observed transaction

  function new(mailbox #(fifo_transaction) mon2scb);
    this.mon2scb = mon2scb;
  endfunction

  task run();
    fifo_transaction tr;
    forever begin
      mon2scb.get(tr);
      check(tr);
    end
  endtask

  function int unsigned expected_occupancy();
    return unsigned'(expected_queue.size());
  endfunction

  //----------------------------------------------------------------------------
  // Per-cycle check
  //----------------------------------------------------------------------------
  function void check(fifo_transaction tr);
    bit          exp_wr_accept;
    bit          exp_rd_accept;
    bit          exp_full, exp_empty, exp_afull, exp_aempty;
    int unsigned occ;
    string       problems;
    string       op = tr.op_name();

    num_checked++;
    last_tr = tr;

    // ---- 1-3: acceptance from the model's own occupancy, then update ------
    if (tr.rst) begin
      expected_queue.delete();
      expected_data_out = '0;
      num_resets++;
    end else begin
      occ           = unsigned'(expected_queue.size());   // before the edge
      exp_wr_accept = tr.wr_en && (occ < DEPTH);
      exp_rd_accept = tr.rd_en && (occ > 0);

      if (exp_rd_accept) expected_data_out = expected_queue.pop_front();
      if (exp_wr_accept) expected_queue.push_back(tr.data_in);

      if (exp_wr_accept)  num_writes++;
      else if (tr.wr_en)  num_ignored_writes++;
      if (exp_rd_accept)  num_reads++;
      else if (tr.rd_en)  num_ignored_reads++;
      if (exp_wr_accept && exp_rd_accept) num_simultaneous++;
    end

    // ---- 4-6: expected response after the edge -----------------------------
    occ        = unsigned'(expected_queue.size());
    exp_full   = (occ == DEPTH);
    exp_empty  = (occ == 0);
    exp_afull  = (occ >= ALMOST_FULL_LEVEL);
    exp_aempty = (occ <= ALMOST_EMPTY_LEVEL);
    if (occ > max_occupancy) max_occupancy = occ;

    if (tr.outputs_unknown)
      problems = {problems, " X/Z on a DUT output;"};
    if (tr.data_out != expected_data_out)
      problems = {problems, $sformatf(" data_out expected=0x%0h actual=0x%0h;",
                                      expected_data_out, tr.data_out)};
    if (tr.full != exp_full)
      problems = {problems, $sformatf(" full expected=%0b;", exp_full)};
    if (tr.empty != exp_empty)
      problems = {problems, $sformatf(" empty expected=%0b;", exp_empty)};
    if (tr.almost_full != exp_afull)
      problems = {problems, $sformatf(" almost_full expected=%0b;", exp_afull)};
    if (tr.almost_empty != exp_aempty)
      problems = {problems, $sformatf(" almost_empty expected=%0b;", exp_aempty)};

    // ---- 7: report ---------------------------------------------------------
    if (problems.len() != 0) begin
      num_errors++;
      $error("[FAIL] t=%0t Transaction %0d: %s data_in=0x%0h |%s | expected: data_out=0x%0h occupancy=%0d full=%0b empty=%0b afull=%0b aempty=%0b | actual: data_out=0x%0h %s",
             tr.timestamp, tr.transaction_id, op, tr.data_in, problems,
             expected_data_out, occ, exp_full, exp_empty, exp_afull, exp_aempty,
             tr.data_out, tr.flags2string());
      if (num_errors >= max_errors)
        $fatal(1, "Scoreboard: %0d mismatches, stopping simulation", num_errors);
    end else if (verbosity >= 1) begin
      string note = "";
      if (tr.wr_en && !exp_wr_accept) note = " (write ignored: full)";
      if (tr.rd_en && !exp_rd_accept) note = " (read ignored: empty)";
      if (tr.rst)
        $display("[PASS] Transaction %0d: RESET", tr.transaction_id);
      else if (exp_rd_accept && exp_wr_accept)
        $display("[PASS] Transaction %0d: WRITE_READ write=0x%0h read expected=0x%0h actual=0x%0h",
                 tr.transaction_id, tr.data_in, expected_data_out, tr.data_out);
      else if (exp_rd_accept)
        $display("[PASS] Transaction %0d: READ expected=0x%0h actual=0x%0h%s",
                 tr.transaction_id, expected_data_out, tr.data_out, note);
      else if (exp_wr_accept)
        $display("[PASS] Transaction %0d: WRITE data=0x%0h%s",
                 tr.transaction_id, tr.data_in, note);
      else if (tr.wr_en || tr.rd_en)
        $display("[PASS] Transaction %0d: %s%s, data_out held at 0x%0h",
                 tr.transaction_id, op, note, tr.data_out);
      else if (verbosity >= 2)
        $display("[PASS] Transaction %0d: IDLE", tr.transaction_id);
    end
  endfunction

  //----------------------------------------------------------------------------
  // End-of-test summary
  //----------------------------------------------------------------------------
  function void report();
    $display("---------------------------------------------------------------");
    $display(" Scoreboard summary");
    $display("---------------------------------------------------------------");
    $display("  cycles checked             : %0d", num_checked);
    $display("  writes accepted            : %0d", num_writes);
    $display("  reads accepted             : %0d", num_reads);
    $display("  simultaneous read+write    : %0d", num_simultaneous);
    $display("  writes ignored (full)      : %0d", num_ignored_writes);
    $display("  reads ignored (empty)      : %0d", num_ignored_reads);
    $display("  resets                     : %0d", num_resets);
    $display("  max occupancy reached      : %0d of %0d", max_occupancy, DEPTH);
    $display("  final model occupancy      : %0d", expected_queue.size());
    $display("  mismatches                 : %0d", num_errors);
  endfunction

endclass : fifo_scoreboard

`endif // FIFO_SCOREBOARD_SV
