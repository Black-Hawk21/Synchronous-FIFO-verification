//------------------------------------------------------------------------------
// File        : fifo_test.sv
// Description : Test library for the class-based testbench.
//
// Select a test at run time with +TESTNAME=<name>. Common run-time options:
//   +NUM_TXN=<n>     transactions for random/stress tests
//   +VERBOSITY=<n>   scoreboard verbosity (0 quiet, 1 per request, 2 all)
//   +MAX_ERRORS=<n>  stop after n scoreboard mismatches (default 10)
//
// Directed tests (section 3.1 of the verification plan):
//   reset_test, basic_write_test, basic_read_test, fill_test, empty_test,
//   overflow_test, underflow_test, simultaneous_rw_test, pointer_wrap_test,
//   reset_mid_operation_test
// Constrained-random tests (section 3.2):
//   random_balanced_test, random_write_heavy_test, random_read_heavy_test,
//   stress_test
//
// Every test starts with two reset cycles. Directed tests additionally check
// their intended end state with expect_state(): the reference model's
// occupancy proves the stimulus did what the test meant, and the last DUT
// flags observed by the monitor must agree with it.
//------------------------------------------------------------------------------
`ifndef FIFO_TEST_SV
`define FIFO_TEST_SV

virtual class fifo_base_test;

  string           name;
  fifo_environment env;
  fifo_generator   gen;
  int unsigned     num_txn;
  int unsigned     check_errors;

  function new(string name, virtual fifo_if #(DATA_WIDTH) vif,
               int unsigned default_num_txn   = 1000,
               int unsigned default_verbosity = 1);
    int unsigned value;
    this.name = name;
    env       = new(vif);
    gen       = env.gen;
    num_txn   = default_num_txn;
    env.scb.verbosity = default_verbosity;
    if ($value$plusargs("NUM_TXN=%d", value))    num_txn = value;
    if ($value$plusargs("VERBOSITY=%d", value))  env.scb.verbosity = value;
    if ($value$plusargs("MAX_ERRORS=%d", value)) env.scb.max_errors = value;
  endfunction

  pure virtual task body();

  task run();
    $display("===============================================================");
    $display(" TEST %s  (DATA_WIDTH=%0d DEPTH=%0d ALMOST_FULL_LEVEL=%0d ALMOST_EMPTY_LEVEL=%0d)",
             name, DATA_WIDTH, DEPTH, ALMOST_FULL_LEVEL, ALMOST_EMPTY_LEVEL);
    $display("===============================================================");
    env.start();
    gen.reset(2);
    body();
    env.wait_for_completion();
    env.report();
  endtask

  function bit passed();
    return (env.scb.num_errors == 0) && (check_errors == 0) &&
           (env.scb.num_checked > 0);
  endfunction

  //----------------------------------------------------------------------------
  // Directed-test checks
  //----------------------------------------------------------------------------
  task expect_state(string what, int unsigned exp_occupancy);
    fifo_transaction last;
    env.wait_for_completion();
    last = env.scb.last_tr;
    if (env.scb.expected_occupancy() == exp_occupancy &&
        last.full         == (exp_occupancy == DEPTH) &&
        last.empty        == (exp_occupancy == 0) &&
        last.almost_full  == (exp_occupancy >= ALMOST_FULL_LEVEL) &&
        last.almost_empty == (exp_occupancy <= ALMOST_EMPTY_LEVEL)) begin
      $display("[CHECK] %s: occupancy=%0d, DUT %s -- OK",
               what, exp_occupancy, last.flags2string());
    end else begin
      check_errors++;
      $error("[CHECK] %s: expected occupancy=%0d, model occupancy=%0d, DUT %s",
             what, exp_occupancy, env.scb.expected_occupancy(),
             last.flags2string());
    end
  endtask

  task expect_data_out(string what, data_t value);
    env.wait_for_completion();
    if (env.scb.last_tr.data_out == value) begin
      $display("[CHECK] %s: data_out=0x%0h -- OK", what, value);
    end else begin
      check_errors++;
      $error("[CHECK] %s: expected data_out=0x%0h, DUT data_out=0x%0h",
             what, value, env.scb.last_tr.data_out);
    end
  endtask

  static function int unsigned min_u(int unsigned a, int unsigned b);
    return (a < b) ? a : b;
  endfunction

endclass : fifo_base_test

//==============================================================================
// Directed tests
//==============================================================================

// Reset clears occupancy, flags and data_out
class reset_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("reset_test", vif); endfunction
  task body();
    gen.idle(2);
    expect_state("after power-on reset", 0);
    expect_data_out("data_out after power-on reset", '0);
    gen.write_value(data_t'('hA5));
    gen.read(1);
    expect_data_out("read back before reset", data_t'('hA5));
    gen.write(3);
    expect_state("entries present before reset", 3);
    gen.reset(1);
    expect_state("after reset with entries present", 0);
    expect_data_out("data_out cleared by reset", '0);
  endtask
endclass

// Write 5 values -> occupancy 5
class basic_write_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("basic_write_test", vif); endfunction
  task body();
    data_t values[5] = '{data_t'('hA5), data_t'('h34), data_t'('h5A),
                         data_t'('hC3), data_t'('h0F)};
    foreach (values[i]) gen.write_value(values[i]);
    expect_state("after 5 writes", min_u(5, DEPTH));
  endtask
endclass

// Write then read 5 values -> data comes back in order
class basic_read_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("basic_read_test", vif); endfunction
  task body();
    data_t values[5] = '{data_t'('hA5), data_t'('h34), data_t'('h5A),
                         data_t'('hC3), data_t'('h0F)};
    int unsigned n = min_u(5, DEPTH);
    foreach (values[i]) gen.write_value(values[i]);
    expect_state("after 5 writes", n);
    gen.read(5);
    expect_state("after 5 reads", 0);
    expect_data_out("last value read", values[n-1]);
  endtask
endclass

// Write DEPTH values -> almost_full then full
class fill_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("fill_test", vif); endfunction
  task body();
    gen.write(ALMOST_FULL_LEVEL);
    expect_state("at ALMOST_FULL_LEVEL", ALMOST_FULL_LEVEL);
    gen.write(DEPTH - ALMOST_FULL_LEVEL);
    expect_state("after DEPTH writes", DEPTH);
  endtask
endclass

// Fill, then read every entry -> almost_empty then empty
class empty_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("empty_test", vif); endfunction
  task body();
    gen.write(DEPTH);
    expect_state("filled", DEPTH);
    gen.read(DEPTH - ALMOST_EMPTY_LEVEL);
    expect_state("at ALMOST_EMPTY_LEVEL", ALMOST_EMPTY_LEVEL);
    gen.read(ALMOST_EMPTY_LEVEL);
    expect_state("after reading every entry", 0);
  endtask
endclass

// Writes while full are ignored: no occupancy change, stored data untouched
class overflow_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("overflow_test", vif); endfunction
  task body();
    gen.write_pattern(DEPTH, data_t'(1));
    expect_state("filled with 1..DEPTH", DEPTH);
    gen.write(4);
    expect_state("after 4 writes while full", DEPTH);
    gen.read(DEPTH);                           // scoreboard: still 1..DEPTH
    expect_state("drained, original data intact", 0);
    expect_data_out("last stored value", data_t'(DEPTH));
  endtask
endclass

// Reads while empty are ignored: data_out holds, no pointer movement
class underflow_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("underflow_test", vif); endfunction
  task body();
    gen.read(3);
    expect_state("3 reads on an empty FIFO", 0);
    expect_data_out("data_out holds reset value", '0);
    gen.write_value(data_t'('h3C));
    gen.read(1);
    expect_data_out("valid read", data_t'('h3C));
    gen.read(3);
    expect_state("3 more reads on an empty FIFO", 0);
    expect_data_out("data_out holds last read value", data_t'('h3C));
    gen.write_value(data_t'('h77));            // pointers did not move:
    gen.read(1);                               // next read returns 0x77
    expect_data_out("first write after underflow", data_t'('h77));
  endtask
endclass

// Simultaneous read+write: normal, while empty (write only), while full (read only)
class simultaneous_rw_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("simultaneous_rw_test", vif); endfunction
  task body();
    gen.write_read(1);
    expect_state("write+read while empty performs only the write", 1);
    gen.write(2);
    expect_state("preloaded", 3);
    gen.write_read(2 * DEPTH);
    expect_state("steady-state write+read keeps occupancy", 3);
    gen.write(DEPTH - 3);
    expect_state("filled", DEPTH);
    gen.write_read(1);
    expect_state("write+read while full performs only the read", DEPTH - 1);
    gen.write_read(DEPTH);
    expect_state("write+read at DEPTH-1 performs both", DEPTH - 1);
    gen.read(DEPTH - 1);
    expect_state("drained", 0);
  endtask
endclass

// Pointers cross the DEPTH-1 -> 0 boundary many times at different offsets
class pointer_wrap_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("pointer_wrap_test", vif); endfunction
  task body();
    repeat (3) begin
      gen.write(DEPTH);
      gen.read(DEPTH);
    end
    expect_state("3 full fill/drain rounds", 0);
    for (int unsigned k = 1; k <= DEPTH; k++) begin   // every relative offset
      gen.write(k);
      gen.read(k);
    end
    expect_state("write k / read k for k = 1..DEPTH", 0);
    gen.write(DEPTH / 2);
    gen.write_read(4 * DEPTH);
    gen.read(DEPTH / 2);
    expect_state("half-full streaming across the wrap point", 0);
  endtask
endclass

// Reset in the middle of traffic returns the FIFO to empty
class reset_mid_operation_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("reset_mid_operation_test", vif); endfunction
  task body();
    gen.write(DEPTH / 2);
    expect_state("half full", DEPTH / 2);
    gen.reset(1, 1'b1, 1'b1);                  // wr_en and rd_en high during reset
    expect_state("reset with requests active", 0);
    gen.write_pattern(3, data_t'('h10));       // normal operation, no stale data
    gen.read(3);
    expect_state("traffic after reset", 0);
    expect_data_out("first data after reset", data_t'('h12));
    gen.write(DEPTH);
    expect_state("full again", DEPTH);
    gen.reset(1);
    expect_state("reset while full", 0);
    gen.read(2);
    expect_state("reads after reset are ignored", 0);
    gen.write(2);
    gen.read(2);
    expect_state("traffic after second reset", 0);
  endtask
endclass

//==============================================================================
// Constrained-random tests
//==============================================================================

class random_test extends fifo_base_test;
  string profile_name;
  function new(string name, virtual fifo_if #(DATA_WIDTH) vif, string profile_name);
    super.new(name, vif, 1000, 0);
    this.profile_name = profile_name;
  endfunction
  task body();
    gen.set_profile(profile_name);
    $display("Random stimulus: profile=%s write/read/both/idle weights=%0d/%0d/%0d/%0d, %0d transactions",
             profile_name, gen.wt_write, gen.wt_read, gen.wt_both, gen.wt_idle, num_txn);
    gen.random(num_txn);
  endtask
endclass

// Blocks of random traffic with a randomly chosen profile per block (so the
// FIFO keeps swinging between empty and full) plus occasional random resets.
class stress_test extends fifo_base_test;
  function new(virtual fifo_if #(DATA_WIDTH) vif); super.new("stress_test", vif, 10000, 0); endfunction
  task body();
    string       profiles[5] = '{"balanced", "write_heavy", "read_heavy",
                                 "fill_burst", "drain_burst"};
    int unsigned remaining   = num_txn;
    gen.rst_permille = 2;
    $display("Stress stimulus: %0d transactions, random profile per block, reset rate %0d/1000",
             num_txn, gen.rst_permille);
    while (remaining > 0) begin
      int unsigned block = $urandom_range(400, 50);
      if (block > remaining) block = remaining;
      gen.set_profile(profiles[$urandom_range(4, 0)]);
      gen.random(block);
      remaining -= block;
    end
  endtask
endclass

//==============================================================================
// Test selection
//==============================================================================
class fifo_test_factory;

  static function void list_tests();
    $display("Available tests:");
    $display("  directed: reset_test basic_write_test basic_read_test fill_test empty_test");
    $display("            overflow_test underflow_test simultaneous_rw_test pointer_wrap_test");
    $display("            reset_mid_operation_test");
    $display("  random  : random_balanced_test random_write_heavy_test random_read_heavy_test");
    $display("            stress_test");
  endfunction

  static function fifo_base_test create(string name, virtual fifo_if #(DATA_WIDTH) vif);
    case (name)
      "reset_test":               begin reset_test               t = new(vif); return t; end
      "basic_write_test":         begin basic_write_test         t = new(vif); return t; end
      "basic_read_test":          begin basic_read_test          t = new(vif); return t; end
      "fill_test":                begin fill_test                t = new(vif); return t; end
      "empty_test":               begin empty_test               t = new(vif); return t; end
      "overflow_test":            begin overflow_test            t = new(vif); return t; end
      "underflow_test":           begin underflow_test           t = new(vif); return t; end
      "simultaneous_rw_test":     begin simultaneous_rw_test     t = new(vif); return t; end
      "pointer_wrap_test":        begin pointer_wrap_test        t = new(vif); return t; end
      "reset_mid_operation_test": begin reset_mid_operation_test t = new(vif); return t; end
      "random_balanced_test":     begin random_test t = new(name, vif, "balanced");    return t; end
      "random_write_heavy_test":  begin random_test t = new(name, vif, "write_heavy"); return t; end
      "random_read_heavy_test":   begin random_test t = new(name, vif, "read_heavy");  return t; end
      "stress_test":              begin stress_test              t = new(vif); return t; end
      default: begin
        list_tests();
        $fatal(1, "Unknown test '%s'", name);
      end
    endcase
    return null;
  endfunction

endclass : fifo_test_factory

`endif // FIFO_TEST_SV
