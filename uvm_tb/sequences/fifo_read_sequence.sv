//------------------------------------------------------------------------------
// File        : fifo_read_sequence.sv
// Description : num_items consecutive reads (issued even if the FIFO is empty).
//------------------------------------------------------------------------------
`ifndef FIFO_READ_SEQUENCE_SV
`define FIFO_READ_SEQUENCE_SV

class fifo_read_sequence extends fifo_base_sequence;

  `uvm_object_utils(fifo_read_sequence)

  function new(string name = "fifo_read_sequence");
    super.new(name);
  endfunction

  virtual task body();
    repeat (num_items) send(1'b0, 1'b0, 1'b1);
  endtask

endclass : fifo_read_sequence

`endif // FIFO_READ_SEQUENCE_SV
