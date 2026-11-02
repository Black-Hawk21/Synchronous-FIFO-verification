//------------------------------------------------------------------------------
// File        : fifo_reset_sequence.sv
// Description : Holds the synchronous reset for num_items cycles. wr_en and
//               rd_en can be raised during reset to check that reset wins.
//------------------------------------------------------------------------------
`ifndef FIFO_RESET_SEQUENCE_SV
`define FIFO_RESET_SEQUENCE_SV

class fifo_reset_sequence extends fifo_base_sequence;

  `uvm_object_utils(fifo_reset_sequence)

  bit wr_en_during_reset = 1'b0;
  bit rd_en_during_reset = 1'b0;

  function new(string name = "fifo_reset_sequence");
    super.new(name);
    num_items = 2;
  endfunction

  virtual task body();
    repeat (num_items) send(1'b1, wr_en_during_reset, rd_en_during_reset);
  endtask

endclass : fifo_reset_sequence

`endif // FIFO_RESET_SEQUENCE_SV
