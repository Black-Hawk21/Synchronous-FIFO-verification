//------------------------------------------------------------------------------
// File        : fifo_base_test.sv
// Description : Base class for all UVM tests.
//
//   build_phase   : creates the environment, gets the virtual interface.
//   run_phase     : raises an objection, applies 2 reset cycles, runs the
//                   test's run_scenario(), waits for the last item to be
//                   checked, then drops the objection (end of simulation).
//   final_phase   : prints TEST PASSED / TEST FAILED. A failed test ends
//                   with $fatal so the simulator exits with non-zero status
//                   (pre_abort() does the same if the run is aborted early).
//
// Helper tasks (do_write, do_read, ...) start the building-block sequences on
// the agent's sequencer. expect_state()/expect_data_out() check a directed
// test's intended end state against the reference model and the DUT flags.
//
// Run-time options: +UVM_TESTNAME=<test>  +NUM_TXN=<n>  +MAX_ERRORS=<n>
//------------------------------------------------------------------------------
`ifndef FIFO_BASE_TEST_SV
`define FIFO_BASE_TEST_SV

class fifo_base_test extends uvm_test;

  `uvm_component_utils(fifo_base_test)

  fifo_env                      env;
  virtual fifo_if #(DATA_WIDTH) vif;

  int unsigned num_txn    = 1000;
  int unsigned max_errors = 10;
  int unsigned check_errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = fifo_env::type_id::create("env", this);
    if (!uvm_config_db #(virtual fifo_if #(DATA_WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' was not set for the test")
    void'($value$plusargs("NUM_TXN=%d", num_txn));
    void'($value$plusargs("MAX_ERRORS=%d", max_errors));
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
              $sformatf("DUT configuration: DATA_WIDTH=%0d DEPTH=%0d ALMOST_FULL_LEVEL=%0d ALMOST_EMPTY_LEVEL=%0d",
                        DATA_WIDTH, DEPTH, ALMOST_FULL_LEVEL, ALMOST_EMPTY_LEVEL), UVM_NONE)
    uvm_root::get().print_topology();
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    // Stop the run after max_errors UVM_ERRORs (scoreboard, checks, SVA)
    uvm_report_server::get_server().set_max_quit_count(int'(max_errors));
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "test running");
    do_reset(2);
    run_scenario();
    wait_for_checks();
    phase.drop_objection(this, "test done");
  endtask

  // Overridden by each test
  virtual task run_scenario();
  endtask

  //----------------------------------------------------------------------------
  // Building blocks
  //----------------------------------------------------------------------------
  task do_reset(int unsigned cycles, bit wr_en = 1'b0, bit rd_en = 1'b0);
    fifo_reset_sequence seq = fifo_reset_sequence::type_id::create("reset_seq");
    seq.num_items          = cycles;
    seq.wr_en_during_reset = wr_en;
    seq.rd_en_during_reset = rd_en;
    seq.start(env.agent.sqr);
  endtask

  task do_idle(int unsigned n);
    fifo_idle_sequence seq = fifo_idle_sequence::type_id::create("idle_seq");
    seq.num_items = n;
    seq.start(env.agent.sqr);
  endtask

  task do_write(int unsigned n);
    fifo_write_sequence seq = fifo_write_sequence::type_id::create("write_seq");
    seq.num_items = n;
    seq.start(env.agent.sqr);
  endtask

  task do_write_pattern(int unsigned n, data_t first_value);
    fifo_write_sequence seq = fifo_write_sequence::type_id::create("write_seq");
    seq.num_items   = n;
    seq.use_pattern = 1'b1;
    seq.first_value = first_value;
    seq.start(env.agent.sqr);
  endtask

  task do_write_values(data_t values[$]);
    fifo_write_sequence seq = fifo_write_sequence::type_id::create("write_seq");
    seq.values = values;
    seq.start(env.agent.sqr);
  endtask

  task do_read(int unsigned n);
    fifo_read_sequence seq = fifo_read_sequence::type_id::create("read_seq");
    seq.num_items = n;
    seq.start(env.agent.sqr);
  endtask

  task do_write_read(int unsigned n);
    fifo_rw_sequence seq = fifo_rw_sequence::type_id::create("rw_seq");
    seq.num_items = n;
    seq.start(env.agent.sqr);
  endtask

  // The last item of a sequence is driven on a falling edge, consumed on the
  // next rising edge and observed on the falling edge after that; one more
  // falling edge guarantees the scoreboard has processed it.
  task wait_for_checks();
    repeat (2) @(vif.drv_cb);
  endtask

  //----------------------------------------------------------------------------
  // Directed-test checks
  //----------------------------------------------------------------------------
  task expect_state(string what, int unsigned exp_occupancy);
    fifo_sequence_item last;
    wait_for_checks();
    last = env.scb.last_item;
    if (env.scb.expected_occupancy() == exp_occupancy &&
        last.full         == (exp_occupancy == DEPTH) &&
        last.empty        == (exp_occupancy == 0) &&
        last.almost_full  == (exp_occupancy >= ALMOST_FULL_LEVEL) &&
        last.almost_empty == (exp_occupancy <= ALMOST_EMPTY_LEVEL)) begin
      `uvm_info("CHECK", $sformatf("[CHECK] %s: occupancy=%0d, DUT %s -- OK",
                                   what, exp_occupancy, last.flags2string()), UVM_LOW)
    end else begin
      check_errors++;
      `uvm_error("CHECK", $sformatf("[CHECK] %s: expected occupancy=%0d, model occupancy=%0d, DUT %s",
                                    what, exp_occupancy, env.scb.expected_occupancy(),
                                    last.flags2string()))
    end
  endtask

  task expect_data_out(string what, data_t value);
    wait_for_checks();
    if (env.scb.last_item.data_out == value)
      `uvm_info("CHECK", $sformatf("[CHECK] %s: data_out=0x%0h -- OK", what, value), UVM_LOW)
    else begin
      check_errors++;
      `uvm_error("CHECK", $sformatf("[CHECK] %s: expected data_out=0x%0h, DUT data_out=0x%0h",
                                    what, value, env.scb.last_item.data_out))
    end
  endtask

  static function int unsigned min_u(int unsigned a, int unsigned b);
    return (a < b) ? a : b;
  endfunction

  //----------------------------------------------------------------------------
  // Verdict
  //----------------------------------------------------------------------------
  function void final_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    int errors = svr.get_severity_count(UVM_ERROR) +
                 svr.get_severity_count(UVM_FATAL);
    $display("===============================================================");
    if (errors == 0 && env.scb.num_checked > 0) begin
      $display("TEST PASSED: %s (%0d cycles checked, 0 mismatches, 0 assertion failures)",
               get_type_name(), env.scb.num_checked);
      $display("===============================================================");
    end else begin
      $display("TEST FAILED: %s (UVM errors=%0d, scoreboard mismatches=%0d, check failures=%0d)",
               get_type_name(), errors, env.scb.num_errors, check_errors);
      $display("===============================================================");
      svr.report_summarize();
      $fatal(1, "TEST FAILED: %s", get_type_name());
    end
  endfunction

  // Called instead of the remaining phases when the run is aborted, e.g. when
  // the UVM_ERROR count reaches max_quit_count. Keep the verdict and the exit
  // status consistent with final_phase.
  virtual function void pre_abort();
    uvm_report_server svr = uvm_report_server::get_server();
    $display("===============================================================");
    $display("TEST FAILED: %s (aborted after %0d UVM errors)",
             get_type_name(), svr.get_severity_count(UVM_ERROR));
    $display("===============================================================");
    svr.report_summarize();
    $fatal(1, "TEST FAILED: %s", get_type_name());
  endfunction

endclass : fifo_base_test

`endif // FIFO_BASE_TEST_SV
