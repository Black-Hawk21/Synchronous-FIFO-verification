//------------------------------------------------------------------------------
// File        : fifo_driver.sv
// Description : Drives sequence items onto the FIFO pins.
//
//   * One item = one clock cycle, applied through drv_cb on the falling edge.
//   * Sequencer handshake: get_next_item() / item_done().
//   * On each falling edge the driver takes an item only if the sequencer has
//     one ready (has_do_available()); otherwise it drives an idle cycle, so a
//     request is never held for more than one cycle.
//   * Requests are never filtered: overflow/underflow attempts reach the DUT.
//------------------------------------------------------------------------------
`ifndef FIFO_DRIVER_SV
`define FIFO_DRIVER_SV

class fifo_driver extends uvm_driver #(fifo_sequence_item);

  `uvm_component_utils(fifo_driver)

  virtual fifo_if #(DATA_WIDTH) vif;

  int unsigned num_driven;
  int unsigned num_idle;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(virtual fifo_if #(DATA_WIDTH))::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "virtual interface 'vif' was not set for the driver")
  endfunction

  task run_phase(uvm_phase phase);
    // Known input values before the first clock edge (run_phase starts at t=0)
    vif.rst_n   = 1'b0;
    vif.wr_en   = 1'b0;
    vif.rd_en   = 1'b0;
    vif.data_in = '0;

    forever begin
      @(vif.drv_cb);
      if (seq_item_port.has_do_available()) begin
        seq_item_port.get_next_item(req);
        drive(req);
        seq_item_port.item_done();
        num_driven++;
      end else begin
        drive_idle();
        num_idle++;
      end
    end
  endtask

  protected task drive(fifo_sequence_item item);
    vif.drv_cb.rst_n   <= !item.rst;
    vif.drv_cb.wr_en   <= item.wr_en;
    vif.drv_cb.rd_en   <= item.rd_en;
    vif.drv_cb.data_in <= item.data_in;
  endtask

  protected task drive_idle();
    vif.drv_cb.rst_n <= 1'b1;
    vif.drv_cb.wr_en <= 1'b0;
    vif.drv_cb.rd_en <= 1'b0;
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("items driven: %0d, idle cycles inserted: %0d",
                                         num_driven, num_idle), UVM_MEDIUM)
  endfunction

endclass : fifo_driver

`endif // FIFO_DRIVER_SV
