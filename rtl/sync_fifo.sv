//------------------------------------------------------------------------------
// File        : sync_fifo.sv
// Project     : Parameterized Synchronous FIFO - Design Verification
// Description : Single-clock synchronous FIFO.
//
//   * Synchronous, active-low reset (rst_n) clears both pointers, the
//     occupancy counter and data_out. The storage array is not reset.
//   * Any DEPTH >= 2 is supported (not only powers of two): both pointers
//     wrap explicitly from DEPTH-1 back to 0.
//   * Read/write acceptance is decided from the status flags as they are
//     immediately before the active clock edge:
//         wr_accept = wr_en & ~full
//         rd_accept = rd_en & ~empty
//     Consequently a simultaneous read+write performs only the read when the
//     FIFO is full, and only the write when it is empty.
//   * data_out is registered: it loads the oldest entry on an accepted read
//     and otherwise holds its previous value.
//   * All status flags are decoded from the registered occupancy counter.
//------------------------------------------------------------------------------
`timescale 1ns/1ps

module sync_fifo #(
  parameter int DATA_WIDTH         = 8,
  parameter int DEPTH              = 16,
  parameter int ALMOST_FULL_LEVEL  = 14,
  parameter int ALMOST_EMPTY_LEVEL = 1
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  wr_en,
  input  logic                  rd_en,
  input  logic [DATA_WIDTH-1:0] data_in,
  output logic [DATA_WIDTH-1:0] data_out,
  output logic                  full,
  output logic                  empty,
  output logic                  almost_full,
  output logic                  almost_empty
);

  //----------------------------------------------------------------------------
  // Derived widths and constants
  //----------------------------------------------------------------------------
  localparam int PTR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1;  // indexes 0 .. DEPTH-1
  localparam int CNT_W = $clog2(DEPTH + 1);                // holds   0 .. DEPTH

  localparam logic [PTR_W-1:0] PTR_LAST = PTR_W'(DEPTH - 1);
  localparam logic [CNT_W-1:0] CNT_FULL = CNT_W'(DEPTH);
  localparam logic [CNT_W-1:0] CNT_AF   = CNT_W'(ALMOST_FULL_LEVEL);
  localparam logic [CNT_W-1:0] CNT_AE   = CNT_W'(ALMOST_EMPTY_LEVEL);

  //----------------------------------------------------------------------------
  // Parameter validation (elaboration time)
  //----------------------------------------------------------------------------
  if (DATA_WIDTH < 1) begin : g_bad_data_width
    $error("sync_fifo: DATA_WIDTH must be >= 1 (got %0d)", DATA_WIDTH);
  end
  if (DEPTH < 2) begin : g_bad_depth
    $error("sync_fifo: DEPTH must be >= 2 (got %0d)", DEPTH);
  end
  if ((ALMOST_FULL_LEVEL < 1) || (ALMOST_FULL_LEVEL > DEPTH)) begin : g_bad_af_level
    $error("sync_fifo: ALMOST_FULL_LEVEL must be in [1, DEPTH=%0d] (got %0d)",
           DEPTH, ALMOST_FULL_LEVEL);
  end
  if ((ALMOST_EMPTY_LEVEL < 0) || (ALMOST_EMPTY_LEVEL >= DEPTH)) begin : g_bad_ae_level
    $error("sync_fifo: ALMOST_EMPTY_LEVEL must be in [0, DEPTH-1=%0d] (got %0d)",
           DEPTH - 1, ALMOST_EMPTY_LEVEL);
  end

  //----------------------------------------------------------------------------
  // Storage and state
  //----------------------------------------------------------------------------
  logic [DATA_WIDTH-1:0] mem [DEPTH];

  logic [PTR_W-1:0] wr_ptr, wr_ptr_next;
  logic [PTR_W-1:0] rd_ptr, rd_ptr_next;
  logic [CNT_W-1:0] count,  count_next;

  logic wr_accept;
  logic rd_accept;

  //----------------------------------------------------------------------------
  // Status flags: pure decodes of the registered occupancy counter
  //----------------------------------------------------------------------------
  assign full         = (count == CNT_FULL);
  assign empty        = (count == '0);
  assign almost_full  = (count >= CNT_AF);
  assign almost_empty = (count <= CNT_AE);

  //----------------------------------------------------------------------------
  // Acceptance: uses the flags as they are before the active clock edge.
  // These are the only conditions under which state may change, so the
  // pointers never move on an invalid request and count cannot over/underflow.
  //----------------------------------------------------------------------------
  assign wr_accept = wr_en && !full;
  assign rd_accept = rd_en && !empty;

  //----------------------------------------------------------------------------
  // Next-state logic (combinational)
  //----------------------------------------------------------------------------
  always_comb begin : write_pointer_next
    wr_ptr_next = wr_ptr;
    if (wr_accept) begin
      if (wr_ptr == PTR_LAST) wr_ptr_next = '0;          // explicit wrap
      else                    wr_ptr_next = wr_ptr + 1'b1;
    end
  end

  always_comb begin : read_pointer_next
    rd_ptr_next = rd_ptr;
    if (rd_accept) begin
      if (rd_ptr == PTR_LAST) rd_ptr_next = '0;          // explicit wrap
      else                    rd_ptr_next = rd_ptr + 1'b1;
    end
  end

  always_comb begin : occupancy_next
    case ({wr_accept, rd_accept})
      2'b10:   count_next = count + 1'b1;   // write only
      2'b01:   count_next = count - 1'b1;   // read only
      default: count_next = count;          // both, or neither
    endcase
  end

  //----------------------------------------------------------------------------
  // State registers (synchronous active-low reset)
  //----------------------------------------------------------------------------
  always_ff @(posedge clk) begin : state_regs
    if (!rst_n) begin
      wr_ptr   <= '0;
      rd_ptr   <= '0;
      count    <= '0;
      data_out <= '0;
    end else begin
      wr_ptr <= wr_ptr_next;
      rd_ptr <= rd_ptr_next;
      count  <= count_next;
      if (rd_accept) begin
        data_out <= mem[rd_ptr];   // registered read of the oldest entry
      end
    end
  end

  //----------------------------------------------------------------------------
  // Storage array: written only on accepted writes, intentionally not reset
  //----------------------------------------------------------------------------
  always_ff @(posedge clk) begin : storage_write
    if (rst_n && wr_accept) begin
      mem[wr_ptr] <= data_in;
    end
  end

endmodule : sync_fifo
