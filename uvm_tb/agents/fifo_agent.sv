//------------------------------------------------------------------------------
// File        : fifo_agent.sv
// Description : Groups sequencer, driver and monitor for the FIFO interface.
//               Active by default; a passive agent builds only the monitor.
//------------------------------------------------------------------------------
`ifndef FIFO_AGENT_SV
`define FIFO_AGENT_SV

class fifo_agent extends uvm_agent;

  `uvm_component_utils(fifo_agent)

  fifo_sequencer sqr;
  fifo_driver    drv;
  fifo_monitor   mon;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    mon = fifo_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      sqr = fifo_sequencer::type_id::create("sqr", this);
      drv = fifo_driver::type_id::create("drv", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : fifo_agent

`endif // FIFO_AGENT_SV
