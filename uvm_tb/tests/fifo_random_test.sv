//------------------------------------------------------------------------------
// File        : fifo_random_test.sv
// Description : Constrained-random tests (verification plan, section 3.2).
//
//   fifo_random_test              balanced profile (40/40/15/5), 1000 items
//   fifo_random_write_heavy_test  write-heavy (65/20/10/5)
//   fifo_random_read_heavy_test   read-heavy  (20/65/10/5)
//   fifo_stress_test              10000 items, random profile per block,
//                                 occasional random resets
//
//   +NUM_TXN=<n> changes the number of items; +PROFILE=<name> overrides the
//   profile of fifo_random_test.
//------------------------------------------------------------------------------
`ifndef FIFO_RANDOM_TEST_SV
`define FIFO_RANDOM_TEST_SV

class fifo_random_test extends fifo_base_test;

  `uvm_component_utils(fifo_random_test)

  string profile = "balanced";

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'($value$plusargs("PROFILE=%s", profile));
  endfunction

  virtual task run_scenario();
    fifo_random_sequence seq = fifo_random_sequence::type_id::create("random_seq");
    seq.set_profile(profile);
    seq.num_items = num_txn;
    `uvm_info(get_type_name(),
              $sformatf("random stimulus: profile=%s write/read/both/idle=%0d/%0d/%0d/%0d, %0d items",
                        profile, seq.wt_write, seq.wt_read, seq.wt_both, seq.wt_idle, num_txn),
              UVM_NONE)
    seq.start(env.agent.sqr);
  endtask

endclass : fifo_random_test

class fifo_random_write_heavy_test extends fifo_random_test;
  `uvm_component_utils(fifo_random_write_heavy_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    profile = "write_heavy";
  endfunction
endclass

class fifo_random_read_heavy_test extends fifo_random_test;
  `uvm_component_utils(fifo_random_read_heavy_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
    profile = "read_heavy";
  endfunction
endclass

class fifo_stress_test extends fifo_base_test;

  `uvm_component_utils(fifo_stress_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    num_txn = 10000;
  endfunction

  virtual task run_scenario();
    fifo_stress_sequence seq = fifo_stress_sequence::type_id::create("stress_seq");
    seq.num_items = num_txn;
    `uvm_info(get_type_name(),
              $sformatf("stress stimulus: %0d items, random profile per block, reset rate %0d/1000",
                        num_txn, seq.rst_permille), UVM_NONE)
    seq.start(env.agent.sqr);
  endtask

endclass : fifo_stress_test

`endif // FIFO_RANDOM_TEST_SV
