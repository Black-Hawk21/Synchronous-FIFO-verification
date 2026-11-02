//------------------------------------------------------------------------------
// File        : fifo_driver.sv
// Description : Converts transactions into pin activity.
//
//   * One transaction occupies exactly one clock cycle.
//   * Requests are applied through drv_cb on the falling edge, so they are
//     stable when the DUT samples them on the rising edge.
//   * When the generator has nothing queued, the driver inserts an idle cycle
//     (reset released, no requests) instead of holding the last request.
//   * Reset is ordinary stimulus (rst field), so the monitor observes it on
//     the rst_n pin like any other input.
//   * Requests are never filtered: overflow/underflow attempts reach the DUT.
//------------------------------------------------------------------------------
`ifndef FIFO_DRIVER_SV
`define FIFO_DRIVER_SV

class fifo_driver;

  virtual fifo_if #(DATA_WIDTH) vif;
  mailbox #(fifo_transaction)   gen2drv;

  int unsigned num_driven;   // transactions taken from the generator
  int unsigned num_idle;     // filler idle cycles inserted

  function new(virtual fifo_if #(DATA_WIDTH) vif,
               mailbox #(fifo_transaction) gen2drv);
    this.vif     = vif;
    this.gen2drv = gen2drv;
  endfunction

  // Known input values before the first clock edge: reset asserted, no
  // requests. Called at time 0.
  task init();
    vif.rst_n   = 1'b0;
    vif.wr_en   = 1'b0;
    vif.rd_en   = 1'b0;
    vif.data_in = '0;
  endtask

  task run();
    fifo_transaction tr;
    forever begin
      @(vif.drv_cb);
      if (gen2drv.try_get(tr) > 0) begin
        drive(tr);
        num_driven++;
      end else begin
        drive_idle();
        num_idle++;
      end
    end
  endtask

  local task drive(fifo_transaction tr);
    vif.drv_cb.rst_n   <= !tr.rst;
    vif.drv_cb.wr_en   <= tr.wr_en;
    vif.drv_cb.rd_en   <= tr.rd_en;
    vif.drv_cb.data_in <= tr.data_in;
  endtask

  local task drive_idle();
    vif.drv_cb.rst_n <= 1'b1;
    vif.drv_cb.wr_en <= 1'b0;
    vif.drv_cb.rd_en <= 1'b0;
  endtask

endclass : fifo_driver

`endif // FIFO_DRIVER_SV
