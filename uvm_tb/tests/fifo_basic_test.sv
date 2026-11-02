//------------------------------------------------------------------------------
// File        : fifo_basic_test.sv
// Description : Write 5 known values, check occupancy, read them back in
//               order (basic_write_test + basic_read_test of the plan).
//               Scoreboard PASS lines are enabled for readability.
//------------------------------------------------------------------------------
`ifndef FIFO_BASIC_TEST_SV
`define FIFO_BASIC_TEST_SV

class fifo_basic_test extends fifo_base_test;

  `uvm_component_utils(fifo_basic_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    env.scb.set_report_verbosity_level(UVM_HIGH);
  endfunction

  virtual task run_scenario();
    data_t       values[$] = '{data_t'('hA5), data_t'('h34), data_t'('h5A),
                               data_t'('hC3), data_t'('h0F)};
    int unsigned n         = min_u(5, DEPTH);
    do_write_values(values);
    expect_state("after 5 writes", n);
    do_read(5);
    expect_state("after 5 reads", 0);
    expect_data_out("last value read", values[n-1]);
  endtask

endclass : fifo_basic_test

`endif // FIFO_BASIC_TEST_SV
