//------------------------------------------------------------------------------
// File        : fifo_sequencer.sv
// Description : Arbitrates sequences and hands items to the driver.
//               Replaces the generator-to-driver mailbox of the SV testbench.
//------------------------------------------------------------------------------
`ifndef FIFO_SEQUENCER_SV
`define FIFO_SEQUENCER_SV

class fifo_sequencer extends uvm_sequencer #(fifo_sequence_item);

  `uvm_component_utils(fifo_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : fifo_sequencer

`endif // FIFO_SEQUENCER_SV
