//------------------------------------------------------------------------------
// File        : fifo_interface.sv
// Description : Interface between the class-based testbench and sync_fifo.
//
// Clocking strategy (race-free, no ad-hoc delays):
//
//        drv_cb drives            DUT samples          mon_cb samples
//        request N               request N            request N + result
//            |                       |                      |
//   clk  ____|‾‾‾‾‾‾‾‾‾‾‾|___________|‾‾‾‾‾‾‾‾‾‾‾|__________|‾‾‾‾
//          negedge               posedge                negedge
//
//   * The driver applies a request on the falling edge, half a cycle away
//     from the rising edge on which the DUT samples it.
//   * The monitor also uses the falling edge, with #1step input skew: the
//     values it sees are those just before that edge, i.e. the request the
//     DUT consumed at the preceding rising edge together with the outputs
//     that edge produced, and before the driver applies the next request.
//     One monitor sample therefore describes exactly one complete FIFO
//     operation (request + post-edge response).
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

  // Driver clocking block: requests change on the falling edge
  clocking drv_cb @(negedge clk);
    default input #1step output #0;
    output rst_n, wr_en, rd_en, data_in;
  endclocking

  // Monitor clocking block: request + settled response, sampled together
  clocking mon_cb @(negedge clk);
    default input #1step;
    input rst_n, wr_en, rd_en, data_in;
    input data_out, full, empty, almost_full, almost_empty;
  endclocking

endinterface : fifo_if
