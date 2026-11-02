//------------------------------------------------------------------------------
// File        : fifo_if.sv
// Description : Interface between the UVM testbench and sync_fifo.
//               Same signals and clocking strategy as sv_tb/fifo_interface.sv:
//
//   * drv_cb : the driver applies requests on the falling edge, half a cycle
//              before the rising edge on which the DUT samples them.
//   * mon_cb : the monitor samples on the falling edge with #1step skew, i.e.
//              the request consumed at the preceding rising edge together
//              with the outputs that edge produced, before the next request
//              is applied. One sample = one complete FIFO operation.
//------------------------------------------------------------------------------
`timescale 1ns/1ps

interface fifo_if #(
  parameter int DATA_WIDTH = 8
) (
  input logic clk
);

  // DUT inputs
  logic                  rst_n;
  logic                  wr_en;
  logic                  rd_en;
  logic [DATA_WIDTH-1:0] data_in;

  // DUT outputs
  logic [DATA_WIDTH-1:0] data_out;
  logic                  full;
  logic                  empty;
  logic                  almost_full;
  logic                  almost_empty;

  clocking drv_cb @(negedge clk);
    default input #1step output #0;
    output rst_n, wr_en, rd_en, data_in;
  endclocking

  clocking mon_cb @(negedge clk);
    default input #1step;
    input rst_n, wr_en, rd_en, data_in;
    input data_out, full, empty, almost_full, almost_empty;
  endclocking

endinterface : fifo_if
