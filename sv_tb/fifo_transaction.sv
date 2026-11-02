//------------------------------------------------------------------------------
// File        : fifo_transaction.sv
// Description : One FIFO operation = one clock cycle.
//
// The same class is used in both directions:
//   * Stimulus  (generator -> driver): rst, wr_en, rd_en, data_in
//   * Observed  (monitor -> scoreboard/coverage): the stimulus fields as seen
//     on the pins, plus the DUT response sampled after the clock edge.
//
// Operation mix is controlled with a dist constraint on the {wr_en, rd_en}
// pair, using weights that the generator can change at run time:
//     {wr_en,rd_en} = 2'b10 write-only, 2'b01 read-only,
//                     2'b11 simultaneous, 2'b00 idle
// The driver never filters requests: writes while full and reads while empty
// are generated deliberately, because handling them is part of the spec.
//------------------------------------------------------------------------------
`ifndef FIFO_TRANSACTION_SV
`define FIFO_TRANSACTION_SV

class fifo_transaction;

  //----------------------------------------------------------------------------
  // Stimulus
  //----------------------------------------------------------------------------
  rand bit    rst;      // 1 = synchronous reset this cycle (drives rst_n = 0)
  rand bit    wr_en;
  rand bit    rd_en;
  rand data_t data_in;

  // Distribution knobs (relative weights; set before randomize())
  int unsigned wt_write     = 40;
  int unsigned wt_read      = 40;
  int unsigned wt_both      = 15;
  int unsigned wt_idle      = 5;
  int unsigned rst_permille = 0;    // chance of a random reset per 1000 txns

  //----------------------------------------------------------------------------
  // Observed response (filled in by the monitor)
  //----------------------------------------------------------------------------
  data_t       data_out;
  bit          full;
  bit          empty;
  bit          almost_full;
  bit          almost_empty;
  bit          outputs_unknown;     // X/Z seen on any DUT output

  // Derived by the monitor from what the DUT showed *before* the edge.
  // Used for coverage only; the scoreboard derives its own expectations.
  bit          pre_full;
  bit          pre_empty;
  bit          wr_accept;
  bit          rd_accept;
  int unsigned pre_count;           // occupancy before the edge

  // Metadata
  int unsigned transaction_id;
  time         timestamp;

  //----------------------------------------------------------------------------
  // Constraints
  //----------------------------------------------------------------------------
  // Operation mix (write / read / simultaneous / idle)
  constraint c_op_mix {
    {wr_en, rd_en} dist { 2'b10 := wt_write,
                          2'b01 := wt_read,
                          2'b11 := wt_both,
                          2'b00 := wt_idle };
  }

  // Random resets are off unless a test raises rst_permille
  constraint c_reset {
    rst dist { 1'b1 := rst_permille, 1'b0 := 1000 - rst_permille };
  }

  // Bias data toward the corner values so they are hit at any DATA_WIDTH
  constraint c_data_corners {
    data_in dist { data_t'(0) := 1, DATA_MAX := 1, [1 : DATA_MAX - 1] :/ 18 };
  }

  //----------------------------------------------------------------------------
  // Helpers
  //----------------------------------------------------------------------------
  function void set_weights(int unsigned w_write, int unsigned w_read,
                            int unsigned w_both,  int unsigned w_idle);
    wt_write = w_write;
    wt_read  = w_read;
    wt_both  = w_both;
    wt_idle  = w_idle;
  endfunction

  function string op_name();
    if (rst) return "RESET";
    case ({wr_en, rd_en})
      2'b10:   return "WRITE";
      2'b01:   return "READ";
      2'b11:   return "WRITE_READ";
      default: return "IDLE";
    endcase
  endfunction

  function string flags2string();
    return $sformatf("full=%0b empty=%0b afull=%0b aempty=%0b",
                     full, empty, almost_full, almost_empty);
  endfunction

  function string convert2string();
    return $sformatf("#%0d %-10s data_in=0x%0h | data_out=0x%0h %s",
                     transaction_id, op_name(), data_in, data_out,
                     flags2string());
  endfunction

endclass : fifo_transaction

`endif // FIFO_TRANSACTION_SV
