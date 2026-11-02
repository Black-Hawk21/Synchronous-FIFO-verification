//------------------------------------------------------------------------------
// File        : fifo_idle_sequence.sv
// Description : num_items cycles with no request (state must hold).
//------------------------------------------------------------------------------
`ifndef FIFO_IDLE_SEQUENCE_SV
`define FIFO_IDLE_SEQUENCE_SV

class fifo_idle_sequence extends fifo_base_sequence;

  `uvm_object_utils(fifo_idle_sequence)

  function new(string name = "fifo_idle_sequence");
    super.new(name);
  endfunction

  virtual task body();
    repeat (num_items) send(1'b0, 1'b0, 1'b0);
  endtask

endclass : fifo_idle_sequence

`endif // FIFO_IDLE_SEQUENCE_SV
