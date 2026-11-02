//------------------------------------------------------------------------------
// File        : fifo_env.sv
// Description : Environment: one active agent, the scoreboard and the
//               coverage collector. The monitor's analysis port is broadcast
//               to both subscribers.
//
//        fifo_env
//          +-- agent (sqr -> drv -> DUT, mon)
//          |              mon.ap ---+--> scb.item_export
//          |                        +--> cov.analysis_export
//          +-- scb
//          +-- cov
//------------------------------------------------------------------------------
`ifndef FIFO_ENV_SV
`define FIFO_ENV_SV

class fifo_env extends uvm_env;

  `uvm_component_utils(fifo_env)

  fifo_agent      agent;
  fifo_scoreboard scb;
  fifo_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = fifo_agent::type_id::create("agent", this);
    scb   = fifo_scoreboard::type_id::create("scb", this);
    cov   = fifo_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.mon.ap.connect(scb.item_export);
    agent.mon.ap.connect(cov.analysis_export);
  endfunction

endclass : fifo_env

`endif // FIFO_ENV_SV
