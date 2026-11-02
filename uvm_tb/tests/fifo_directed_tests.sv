//------------------------------------------------------------------------------
// File        : fifo_directed_tests.sv
// Description : Directed tests of the verification plan (section 3.1), built
//               from the building-block sequences. Same scenarios and checks
//               as the class-based testbench. Scoreboard PASS lines enabled.
//------------------------------------------------------------------------------
`ifndef FIFO_DIRECTED_TESTS_SV
`define FIFO_DIRECTED_TESTS_SV

// Common base: verbose scoreboard for directed tests
class fifo_directed_test_base extends fifo_base_test;
  `uvm_component_utils(fifo_directed_test_base)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    env.scb.set_report_verbosity_level(UVM_HIGH);
  endfunction
endclass

// Reset clears occupancy, flags and data_out
class fifo_reset_test extends fifo_directed_test_base;
  `uvm_component_utils(fifo_reset_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_scenario();
    do_idle(2);
    expect_state("after power-on reset", 0);
    expect_data_out("data_out after power-on reset", '0);
    do_write_values('{data_t'('hA5)});
    do_read(1);
    expect_data_out("read back before reset", data_t'('hA5));
    do_write(3);
    expect_state("entries present before reset", 3);
    do_reset(1);
    expect_state("after reset with entries present", 0);
    expect_data_out("data_out cleared by reset", '0);
  endtask
endclass

// Write DEPTH values -> almost_full then full
class fifo_fill_test extends fifo_directed_test_base;
  `uvm_component_utils(fifo_fill_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_scenario();
    do_write(ALMOST_FULL_LEVEL);
    expect_state("at ALMOST_FULL_LEVEL", ALMOST_FULL_LEVEL);
    do_write(DEPTH - ALMOST_FULL_LEVEL);
    expect_state("after DEPTH writes", DEPTH);
  endtask
endclass

// Fill, then read every entry -> almost_empty then empty
class fifo_empty_test extends fifo_directed_test_base;
  `uvm_component_utils(fifo_empty_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_scenario();
    do_write(DEPTH);
    expect_state("filled", DEPTH);
    do_read(DEPTH - ALMOST_EMPTY_LEVEL);
    expect_state("at ALMOST_EMPTY_LEVEL", ALMOST_EMPTY_LEVEL);
    do_read(ALMOST_EMPTY_LEVEL);
    expect_state("after reading every entry", 0);
  endtask
endclass

// Writes while full are ignored
class fifo_overflow_test extends fifo_directed_test_base;
  `uvm_component_utils(fifo_overflow_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_scenario();
    do_write_pattern(DEPTH, data_t'(1));
    expect_state("filled with 1..DEPTH", DEPTH);
    do_write(4);
    expect_state("after 4 writes while full", DEPTH);
    do_read(DEPTH);
    expect_state("drained, original data intact", 0);
    expect_data_out("last stored value", data_t'(DEPTH));
  endtask
endclass

// Reads while empty are ignored; data_out holds
class fifo_underflow_test extends fifo_directed_test_base;
  `uvm_component_utils(fifo_underflow_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_scenario();
    do_read(3);
    expect_state("3 reads on an empty FIFO", 0);
    expect_data_out("data_out holds reset value", '0);
    do_write_values('{data_t'('h3C)});
    do_read(1);
    expect_data_out("valid read", data_t'('h3C));
    do_read(3);
    expect_state("3 more reads on an empty FIFO", 0);
    expect_data_out("data_out holds last read value", data_t'('h3C));
    do_write_values('{data_t'('h77)});
    do_read(1);
    expect_data_out("first write after underflow", data_t'('h77));
  endtask
endclass

// Simultaneous read+write: normal, while empty, while full
class fifo_simultaneous_rw_test extends fifo_directed_test_base;
  `uvm_component_utils(fifo_simultaneous_rw_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_scenario();
    do_write_read(1);
    expect_state("write+read while empty performs only the write", 1);
    do_write(2);
    expect_state("preloaded", 3);
    do_write_read(2 * DEPTH);
    expect_state("steady-state write+read keeps occupancy", 3);
    do_write(DEPTH - 3);
    expect_state("filled", DEPTH);
    do_write_read(1);
    expect_state("write+read while full performs only the read", DEPTH - 1);
    do_write_read(DEPTH);
    expect_state("write+read at DEPTH-1 performs both", DEPTH - 1);
    do_read(DEPTH - 1);
    expect_state("drained", 0);
  endtask
endclass

// Pointers cross the DEPTH-1 -> 0 boundary at every offset
class fifo_pointer_wrap_test extends fifo_directed_test_base;
  `uvm_component_utils(fifo_pointer_wrap_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_scenario();
    repeat (3) begin
      do_write(DEPTH);
      do_read(DEPTH);
    end
    expect_state("3 full fill/drain rounds", 0);
    for (int unsigned k = 1; k <= DEPTH; k++) begin
      do_write(k);
      do_read(k);
    end
    expect_state("write k / read k for k = 1..DEPTH", 0);
    do_write(DEPTH / 2);
    do_write_read(4 * DEPTH);
    do_read(DEPTH / 2);
    expect_state("half-full streaming across the wrap point", 0);
  endtask
endclass

// Reset in the middle of traffic returns the FIFO to empty
class fifo_reset_mid_operation_test extends fifo_directed_test_base;
  `uvm_component_utils(fifo_reset_mid_operation_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  virtual task run_scenario();
    do_write(DEPTH / 2);
    expect_state("half full", DEPTH / 2);
    do_reset(1, 1'b1, 1'b1);
    expect_state("reset with requests active", 0);
    do_write_pattern(3, data_t'('h10));
    do_read(3);
    expect_state("traffic after reset", 0);
    expect_data_out("first data after reset", data_t'('h12));
    do_write(DEPTH);
    expect_state("full again", DEPTH);
    do_reset(1);
    expect_state("reset while full", 0);
    do_read(2);
    expect_state("reads after reset are ignored", 0);
    do_write(2);
    do_read(2);
    expect_state("traffic after second reset", 0);
  endtask
endclass

`endif // FIFO_DIRECTED_TESTS_SV
