//------------------------------------------------------------------------------
// File        : fifo_rw_sequence.sv
// Description : num_items cycles with simultaneous read and write requests
//               (random write data).
//------------------------------------------------------------------------------
`ifndef FIFO_RW_SEQUENCE_SV
`define FIFO_RW_SEQUENCE_SV

class fifo_rw_sequence extends fifo_base_sequence;

  `uvm_object_utils(fifo_rw_sequence)

  function new(string name = "fifo_rw_sequence");
    super.new(name);
  endfunction

  virtual task body();
    repeat (num_items) send(1'b0, 1'b1, 1'b1);
  endtask

endclass : fifo_rw_sequence

`endif // FIFO_RW_SEQUENCE_SV
