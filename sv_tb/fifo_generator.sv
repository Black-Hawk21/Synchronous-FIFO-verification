//------------------------------------------------------------------------------
// File        : fifo_generator.sv
// Description : Creates directed and constrained-random transactions and
//               sends them to the driver through a mailbox.
//
// The generator works purely at transaction level: it knows nothing about
// pins, clocks or the DUT's state. Tests build scenarios by calling the
// directed building blocks (reset/write/read/write_read/idle) and random().
//------------------------------------------------------------------------------
`ifndef FIFO_GENERATOR_SV
`define FIFO_GENERATOR_SV

class fifo_generator;

  mailbox #(fifo_transaction) gen2drv;

  int unsigned num_generated;

  // Weights used by random(); change them with set_profile()/set_weights()
  int unsigned wt_write     = 40;
  int unsigned wt_read      = 40;
  int unsigned wt_both      = 15;
  int unsigned wt_idle      = 5;
  int unsigned rst_permille = 0;
  string       profile      = "balanced";

  function new(mailbox #(fifo_transaction) gen2drv);
    this.gen2drv = gen2drv;
  endfunction

  //----------------------------------------------------------------------------
  // Operation-mix profiles (write / read / simultaneous / idle, in percent)
  //----------------------------------------------------------------------------
  function void set_profile(string name);
    case (name)
      "balanced":    set_weights(40, 40, 15, 5);
      "write_heavy": set_weights(65, 20, 10, 5);
      "read_heavy":  set_weights(20, 65, 10, 5);
      "fill_burst":  set_weights(85,  5, 10, 0);   // used by the stress test
      "drain_burst": set_weights( 5, 85, 10, 0);   // used by the stress test
      default: $fatal(1, "fifo_generator: unknown profile '%s'", name);
    endcase
    profile = name;
  endfunction

  function void set_weights(int unsigned w_write, int unsigned w_read,
                            int unsigned w_both,  int unsigned w_idle);
    wt_write = w_write;
    wt_read  = w_read;
    wt_both  = w_both;
    wt_idle  = w_idle;
    profile  = "custom";
  endfunction

  //----------------------------------------------------------------------------
  // Constrained-random stimulus
  //----------------------------------------------------------------------------
  task random(int unsigned n);
    repeat (n) begin
      fifo_transaction tr = new();
      tr.set_weights(wt_write, wt_read, wt_both, wt_idle);
      tr.rst_permille = rst_permille;
      if (tr.randomize() == 0) $fatal(1, "fifo_generator: randomize() failed");
      send(tr);
    end
  endtask

  //----------------------------------------------------------------------------
  // Directed building blocks
  //----------------------------------------------------------------------------
  // Hold reset for 'cycles' clocks. wr_en/rd_en may be raised during reset
  // to check that reset takes priority over requests.
  task reset(int unsigned cycles = 2, bit wr_en = 1'b0, bit rd_en = 1'b0);
    repeat (cycles) send(make(1'b1, wr_en, rd_en));
  endtask

  // Write n entries with random data
  task write(int unsigned n = 1);
    repeat (n) send(make(1'b0, 1'b1, 1'b0));
  endtask

  // Write one specific value
  task write_value(data_t value);
    fifo_transaction tr = make(1'b0, 1'b1, 1'b0);
    tr.data_in = value;
    send(tr);
  endtask

  // Write n entries with an incrementing pattern (easy to read in logs)
  task write_pattern(int unsigned n, data_t first_value);
    for (int unsigned i = 0; i < n; i++) write_value(first_value + data_t'(i));
  endtask

  task read(int unsigned n = 1);
    repeat (n) send(make(1'b0, 1'b0, 1'b1));
  endtask

  // Simultaneous read + write, random write data
  task write_read(int unsigned n = 1);
    repeat (n) send(make(1'b0, 1'b1, 1'b1));
  endtask

  task idle(int unsigned n = 1);
    repeat (n) send(make(1'b0, 1'b0, 1'b0));
  endtask

  //----------------------------------------------------------------------------
  // Internals
  //----------------------------------------------------------------------------
  // Directed item: randomize first (random data with corner bias), then pin
  // the control fields.
  local function fifo_transaction make(bit rst, bit wr_en, bit rd_en);
    fifo_transaction tr = new();
    if (tr.randomize() == 0) $fatal(1, "fifo_generator: randomize() failed");
    tr.rst   = rst;
    tr.wr_en = wr_en;
    tr.rd_en = rd_en;
    return tr;
  endfunction

  local task send(fifo_transaction tr);
    tr.transaction_id = num_generated++;
    gen2drv.put(tr);
  endtask

endclass : fifo_generator

`endif // FIFO_GENERATOR_SV
