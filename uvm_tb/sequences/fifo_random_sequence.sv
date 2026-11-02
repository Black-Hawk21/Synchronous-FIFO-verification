//------------------------------------------------------------------------------
// File        : fifo_random_sequence.sv
// Description : num_items constrained-random items. The operation mix comes
//               from the item's dist constraint, using this sequence's
//               weights (see set_profile()).
//------------------------------------------------------------------------------
`ifndef FIFO_RANDOM_SEQUENCE_SV
`define FIFO_RANDOM_SEQUENCE_SV

class fifo_random_sequence extends fifo_base_sequence;

  `uvm_object_utils(fifo_random_sequence)

  int unsigned wt_write     = 40;
  int unsigned wt_read      = 40;
  int unsigned wt_both      = 15;
  int unsigned wt_idle      = 5;
  int unsigned rst_permille = 0;
  string       profile      = "balanced";

  function new(string name = "fifo_random_sequence");
    super.new(name);
    num_items = 1000;
  endfunction

  // Operation-mix profiles: write / read / simultaneous / idle (percent)
  function void set_profile(string name);
    case (name)
      "balanced":    set_weights(40, 40, 15, 5);
      "write_heavy": set_weights(65, 20, 10, 5);
      "read_heavy":  set_weights(20, 65, 10, 5);
      "fill_burst":  set_weights(85,  5, 10, 0);
      "drain_burst": set_weights( 5, 85, 10, 0);
      default: `uvm_fatal("PROFILE", $sformatf("unknown profile '%s'", name))
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

  virtual task body();
    repeat (num_items) begin
      fifo_sequence_item item = fifo_sequence_item::type_id::create("item");
      start_item(item);
      item.set_weights(wt_write, wt_read, wt_both, wt_idle);
      item.rst_permille = rst_permille;
      if (item.randomize() == 0) `uvm_fatal("RAND", "fifo_sequence_item randomize() failed")
      finish_item(item);
    end
  endtask

endclass : fifo_random_sequence

`endif // FIFO_RANDOM_SEQUENCE_SV
