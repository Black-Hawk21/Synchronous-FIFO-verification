//------------------------------------------------------------------------------
// File        : fifo_scoreboard.sv
// Description : Checks every observed cycle against an independent reference
//               model: a queue plus the expected registered output.
//
// The model never uses the DUT's flags to decide what should happen.
// Acceptance comes from the model's own occupancy before the edge:
//     write accepted <=> wr_en && occupancy <  DEPTH
//     read  accepted <=> rd_en && occupancy >  0
// data_out and all four flags are compared on every cycle.
//
// Mismatches are reported with `uvm_error (counted by the report server);
// PASS lines use UVM_HIGH (accepted/ignored requests) and UVM_DEBUG (idle).
//------------------------------------------------------------------------------
`ifndef FIFO_SCOREBOARD_SV
`define FIFO_SCOREBOARD_SV

class fifo_scoreboard extends uvm_scoreboard;

  `uvm_component_utils(fifo_scoreboard)

  uvm_analysis_imp #(fifo_sequence_item, fifo_scoreboard) item_export;

  // Reference model
  data_t expected_queue[$];
  data_t expected_data_out = '0;

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

  fifo_sequence_item last_item;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_export = new("item_export", this);
  endfunction

  function int unsigned expected_occupancy();
    return unsigned'(expected_queue.size());
  endfunction

  // Called by the monitor's analysis port for every observed cycle
  function void write(fifo_sequence_item tr);
    bit          exp_wr_accept;
    bit          exp_rd_accept;
    bit          exp_full, exp_empty, exp_afull, exp_aempty;
    int unsigned occ;
    string       problems;
    string       note;
    string       op = tr.op_name();

    num_checked++;
    last_item = tr;

    // ---- model update ------------------------------------------------------
    if (tr.rst) begin
      expected_queue.delete();
      expected_data_out = '0;
      num_resets++;
    end else begin
      occ           = unsigned'(expected_queue.size());
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

    // ---- expected response ---------------------------------------------------
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

    // ---- report --------------------------------------------------------------
    if (problems.len() != 0) begin
      num_errors++;
      `uvm_error("SCB_MISMATCH",
        $sformatf("[FAIL] t=%0t Transaction %0d: %s data_in=0x%0h |%s | expected: data_out=0x%0h occupancy=%0d full=%0b empty=%0b afull=%0b aempty=%0b | actual: data_out=0x%0h %s",
                  tr.sample_time, tr.cycle_id, op, tr.data_in, problems,
                  expected_data_out, occ, exp_full, exp_empty, exp_afull, exp_aempty,
                  tr.data_out, tr.flags2string()))
      return;
    end

    if (tr.wr_en && !exp_wr_accept) note = " (write ignored: full)";
    if (tr.rd_en && !exp_rd_accept) note = " (read ignored: empty)";
    if (tr.rst)
      `uvm_info("SCB", $sformatf("[PASS] Transaction %0d: RESET", tr.cycle_id), UVM_HIGH)
    else if (exp_rd_accept && exp_wr_accept)
      `uvm_info("SCB", $sformatf("[PASS] Transaction %0d: WRITE_READ write=0x%0h read expected=0x%0h actual=0x%0h",
                                 tr.cycle_id, tr.data_in, expected_data_out, tr.data_out), UVM_HIGH)
    else if (exp_rd_accept)
      `uvm_info("SCB", $sformatf("[PASS] Transaction %0d: READ expected=0x%0h actual=0x%0h%s",
                                 tr.cycle_id, expected_data_out, tr.data_out, note), UVM_HIGH)
    else if (exp_wr_accept)
      `uvm_info("SCB", $sformatf("[PASS] Transaction %0d: WRITE data=0x%0h%s",
                                 tr.cycle_id, tr.data_in, note), UVM_HIGH)
    else if (tr.wr_en || tr.rd_en)
      `uvm_info("SCB", $sformatf("[PASS] Transaction %0d: %s%s, data_out held at 0x%0h",
                                 tr.cycle_id, op, note, tr.data_out), UVM_HIGH)
    else
      `uvm_info("SCB", $sformatf("[PASS] Transaction %0d: IDLE", tr.cycle_id), UVM_DEBUG)
  endfunction

  function void report_phase(uvm_phase phase);
    string s;
    s = {s, "\n---------------------------------------------------------------"};
    s = {s, "\n Scoreboard summary"};
    s = {s, "\n---------------------------------------------------------------"};
    s = {s, $sformatf("\n  cycles checked             : %0d", num_checked)};
    s = {s, $sformatf("\n  writes accepted            : %0d", num_writes)};
    s = {s, $sformatf("\n  reads accepted             : %0d", num_reads)};
    s = {s, $sformatf("\n  simultaneous read+write    : %0d", num_simultaneous)};
    s = {s, $sformatf("\n  writes ignored (full)      : %0d", num_ignored_writes)};
    s = {s, $sformatf("\n  reads ignored (empty)      : %0d", num_ignored_reads)};
    s = {s, $sformatf("\n  resets                     : %0d", num_resets)};
    s = {s, $sformatf("\n  max occupancy reached      : %0d of %0d", max_occupancy, DEPTH)};
    s = {s, $sformatf("\n  final model occupancy      : %0d", expected_queue.size())};
    s = {s, $sformatf("\n  mismatches                 : %0d", num_errors)};
    `uvm_info(get_type_name(), s, UVM_NONE)
  endfunction

endclass : fifo_scoreboard

`endif // FIFO_SCOREBOARD_SV
