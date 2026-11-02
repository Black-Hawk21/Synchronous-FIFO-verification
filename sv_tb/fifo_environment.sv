//------------------------------------------------------------------------------
// File        : fifo_environment.sv
// Description : Builds and connects the verification components.
//
//   Stimulus path    : generator --gen2drv--> driver --> DUT pins
//   Observation path : DUT pins --> monitor --mon2scb--> scoreboard
//                                          \--mon2cov--> coverage
//------------------------------------------------------------------------------
`ifndef FIFO_ENVIRONMENT_SV
`define FIFO_ENVIRONMENT_SV

class fifo_environment;

  virtual fifo_if #(DATA_WIDTH) vif;

  mailbox #(fifo_transaction) gen2drv;
  mailbox #(fifo_transaction) mon2scb;
  mailbox #(fifo_transaction) mon2cov;

  fifo_generator  gen;
  fifo_driver     drv;
  fifo_monitor    mon;
  fifo_scoreboard scb;
  fifo_coverage   cov;

  function new(virtual fifo_if #(DATA_WIDTH) vif);
    this.vif = vif;
    gen2drv  = new();
    mon2scb  = new();
    mon2cov  = new();
    gen      = new(gen2drv);
    drv      = new(vif, gen2drv);
    mon      = new(vif, mon2scb, mon2cov);
    scb      = new(mon2scb);
    cov      = new(mon2cov);
  endfunction

  // Start the free-running components. Must be called at time 0 so the DUT
  // inputs are known before the first clock edge.
  task start();
    drv.init();
    fork
      drv.run();
      mon.run();
      scb.run();
      cov.run();
    join_none
  endtask

  // Return once every transaction handed to the generator has been driven
  // and its result has been observed and checked. The last request is taken
  // by the driver on a falling edge, consumed by the DUT on the next rising
  // edge and sampled by the monitor on the falling edge after that; waiting
  // one further falling edge guarantees the scoreboard has processed it.
  task wait_for_completion();
    while (gen2drv.num() != 0) @(vif.drv_cb);
    repeat (2) @(vif.drv_cb);
  endtask

  function void report();
    scb.report();
    cov.report();
  endfunction

endclass : fifo_environment

`endif // FIFO_ENVIRONMENT_SV
