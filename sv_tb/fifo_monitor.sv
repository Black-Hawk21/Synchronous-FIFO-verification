//------------------------------------------------------------------------------
// File        : fifo_monitor.sv
// Description : Passive observer of the DUT pins.
//
// Every falling edge, mon_cb provides the request the DUT consumed at the
// preceding rising edge and the outputs that edge produced (see
// fifo_interface.sv). The monitor packs both into one observed transaction
// and publishes it to the scoreboard and the coverage collector.
//
// The monitor never talks to the driver. For coverage it also records what
// the DUT itself showed before the edge (pre_full/pre_empty), the resulting
// acceptance, and the occupancy reconstructed from accepted operations.
// The scoreboard ignores those fields and computes its own expectations.
//------------------------------------------------------------------------------
`ifndef FIFO_MONITOR_SV
`define FIFO_MONITOR_SV

class fifo_monitor;

  virtual fifo_if #(DATA_WIDTH) vif;
  mailbox #(fifo_transaction)   mon2scb;
  mailbox #(fifo_transaction)   mon2cov;

  int unsigned num_observed;

  // DUT status carried from the previous sample = status before this edge
  local bit          prev_full  = 1'b0;
  local bit          prev_empty = 1'b1;
  local int unsigned occupancy  = 0;

  function new(virtual fifo_if #(DATA_WIDTH) vif,
               mailbox #(fifo_transaction) mon2scb,
               mailbox #(fifo_transaction) mon2cov);
    this.vif     = vif;
    this.mon2scb = mon2scb;
    this.mon2cov = mon2cov;
  endfunction

  task run();
    forever begin
      fifo_transaction tr;
      @(vif.mon_cb);
      tr = new();

      // Request consumed at the preceding rising edge
      tr.rst     = !vif.mon_cb.rst_n;
      tr.wr_en   = vif.mon_cb.wr_en;
      tr.rd_en   = vif.mon_cb.rd_en;
      tr.data_in = vif.mon_cb.data_in;

      // Response produced by that edge
      tr.outputs_unknown = $isunknown({vif.mon_cb.data_out, vif.mon_cb.full,
                                       vif.mon_cb.empty, vif.mon_cb.almost_full,
                                       vif.mon_cb.almost_empty});
      tr.data_out     = vif.mon_cb.data_out;
      tr.full         = vif.mon_cb.full;
      tr.empty        = vif.mon_cb.empty;
      tr.almost_full  = vif.mon_cb.almost_full;
      tr.almost_empty = vif.mon_cb.almost_empty;

      // Coverage helpers: what the DUT showed before the edge
      tr.pre_full  = prev_full;
      tr.pre_empty = prev_empty;
      tr.pre_count = occupancy;
      if (tr.rst) begin
        tr.wr_accept = 1'b0;
        tr.rd_accept = 1'b0;
        occupancy    = 0;
      end else begin
        tr.wr_accept = tr.wr_en && !tr.pre_full;
        tr.rd_accept = tr.rd_en && !tr.pre_empty;
        if (tr.wr_accept && !tr.rd_accept)                  occupancy++;
        else if (tr.rd_accept && !tr.wr_accept && occupancy > 0) occupancy--;
      end
      prev_full  = tr.full;
      prev_empty = tr.empty;

      tr.transaction_id = num_observed++;
      tr.timestamp      = $time;

      mon2scb.put(tr);
      mon2cov.put(tr);
    end
  endtask

endclass : fifo_monitor

`endif // FIFO_MONITOR_SV
