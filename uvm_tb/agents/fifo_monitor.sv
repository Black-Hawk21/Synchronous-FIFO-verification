//------------------------------------------------------------------------------
// File        : fifo_monitor.sv
// Description : Passive monitor. Every falling edge it packs the request the
//               DUT consumed at the preceding rising edge and the response
//               that edge produced into one item, and broadcasts it through
//               the analysis port (to the scoreboard and coverage).
//
// For coverage it also records the DUT status before the edge, the resulting
// acceptance and the occupancy reconstructed from accepted operations; the
// scoreboard ignores those fields and derives its own expectations.
//------------------------------------------------------------------------------
`ifndef FIFO_MONITOR_SV
`define FIFO_MONITOR_SV

class fifo_monitor extends uvm_monitor;

  `uvm_component_utils(fifo_monitor)

  virtual fifo_if #(DATA_WIDTH) vif;

  uvm_analysis_port #(fifo_sequence_item) ap;

  int unsigned num_observed;

  protected bit          prev_full  = 1'b0;
  protected bit          prev_empty = 1'b1;
  protected int unsigned occupancy  = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual fifo_if #(DATA_WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' was not set for the monitor")
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      fifo_sequence_item tr;
      @(vif.mon_cb);
      tr = fifo_sequence_item::type_id::create("tr");

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

      // Coverage helpers
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
        if (tr.wr_accept && !tr.rd_accept)                       occupancy++;
        else if (tr.rd_accept && !tr.wr_accept && occupancy > 0) occupancy--;
      end
      prev_full  = tr.full;
      prev_empty = tr.empty;

      tr.cycle_id    = num_observed++;
      tr.sample_time = $time;

      `uvm_info(get_type_name(), tr.convert2string(), UVM_DEBUG)
      ap.write(tr);
    end
  endtask

endclass : fifo_monitor

`endif // FIFO_MONITOR_SV
