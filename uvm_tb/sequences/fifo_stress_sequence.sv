//------------------------------------------------------------------------------
// File        : fifo_stress_sequence.sv
// Description : num_items of random traffic split into blocks of 50-400
//               items. Each block runs a fifo_random_sequence with a randomly
//               chosen profile, so the FIFO keeps swinging between empty and
//               full, with occasional random resets.
//------------------------------------------------------------------------------
`ifndef FIFO_STRESS_SEQUENCE_SV
`define FIFO_STRESS_SEQUENCE_SV

class fifo_stress_sequence extends fifo_base_sequence;

  `uvm_object_utils(fifo_stress_sequence)

  int unsigned rst_permille = 2;

  function new(string name = "fifo_stress_sequence");
    super.new(name);
    num_items = 10000;
  endfunction

  virtual task body();
    string       profiles[5] = '{"balanced", "write_heavy", "read_heavy",
                                 "fill_burst", "drain_burst"};
    int unsigned remaining   = num_items;
    while (remaining > 0) begin
      fifo_random_sequence blk = fifo_random_sequence::type_id::create("blk");
      int unsigned         n   = $urandom_range(400, 50);
      if (n > remaining) n = remaining;
      blk.set_profile(profiles[$urandom_range(4, 0)]);
      blk.num_items    = n;
      blk.rst_permille = rst_permille;
      `uvm_info(get_type_name(), $sformatf("block of %0d items, profile %s", n, blk.profile), UVM_HIGH)
      blk.start(m_sequencer, this);
      remaining -= n;
    end
  endtask

endclass : fifo_stress_sequence

`endif // FIFO_STRESS_SEQUENCE_SV
