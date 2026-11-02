//------------------------------------------------------------------------------
// File        : fifo_sequence_item.sv
// Description : One FIFO operation (one clock cycle). Used for stimulus
//               (sequence -> driver) and for observed traffic (monitor ->
//               scoreboard/coverage). UVM equivalent of fifo_transaction.
//------------------------------------------------------------------------------
`ifndef FIFO_SEQUENCE_ITEM_SV
`define FIFO_SEQUENCE_ITEM_SV

class fifo_sequence_item extends uvm_sequence_item;

  `uvm_object_utils(fifo_sequence_item)

  //----------------------------------------------------------------------------
  // Stimulus
  //----------------------------------------------------------------------------
  rand bit    rst;      // 1 = synchronous reset this cycle (rst_n = 0)
  rand bit    wr_en;
  rand bit    rd_en;
  rand data_t data_in;

  // Distribution knobs (relative weights), set before randomize()
  int unsigned wt_write     = 40;
  int unsigned wt_read      = 40;
  int unsigned wt_both      = 15;
  int unsigned wt_idle      = 5;
  int unsigned rst_permille = 0;

  //----------------------------------------------------------------------------
  // Observed response (filled in by the monitor)
  //----------------------------------------------------------------------------
  data_t       data_out;
  bit          full;
  bit          empty;
  bit          almost_full;
  bit          almost_empty;
  bit          outputs_unknown;

  // Coverage helpers derived by the monitor from the DUT status before the edge
  bit          pre_full;
  bit          pre_empty;
  bit          wr_accept;
  bit          rd_accept;
  int unsigned pre_count;

  int unsigned cycle_id;      // monitor sample number
  time         sample_time;

  //----------------------------------------------------------------------------
  // Constraints (same model as the SV testbench)
  //----------------------------------------------------------------------------
  constraint c_op_mix {
    {wr_en, rd_en} dist { 2'b10 := wt_write,
                          2'b01 := wt_read,
                          2'b11 := wt_both,
                          2'b00 := wt_idle };
  }

  constraint c_reset {
    rst dist { 1'b1 := rst_permille, 1'b0 := 1000 - rst_permille };
  }

  constraint c_data_corners {
    data_in dist { data_t'(0) := 1, DATA_MAX := 1, [1 : DATA_MAX - 1] :/ 18 };
  }

  function new(string name = "fifo_sequence_item");
    super.new(name);
  endfunction

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

  virtual function string convert2string();
    return $sformatf("#%0d %-10s data_in=0x%0h | data_out=0x%0h %s",
                     cycle_id, op_name(), data_in, data_out, flags2string());
  endfunction

  virtual function void do_copy(uvm_object rhs);
    fifo_sequence_item rhs_;
    if (!$cast(rhs_, rhs)) `uvm_fatal("CAST", "do_copy: argument is not a fifo_sequence_item")
    super.do_copy(rhs);
    rst             = rhs_.rst;
    wr_en           = rhs_.wr_en;
    rd_en           = rhs_.rd_en;
    data_in         = rhs_.data_in;
    wt_write        = rhs_.wt_write;
    wt_read         = rhs_.wt_read;
    wt_both         = rhs_.wt_both;
    wt_idle         = rhs_.wt_idle;
    rst_permille    = rhs_.rst_permille;
    data_out        = rhs_.data_out;
    full            = rhs_.full;
    empty           = rhs_.empty;
    almost_full     = rhs_.almost_full;
    almost_empty    = rhs_.almost_empty;
    outputs_unknown = rhs_.outputs_unknown;
    pre_full        = rhs_.pre_full;
    pre_empty       = rhs_.pre_empty;
    wr_accept       = rhs_.wr_accept;
    rd_accept       = rhs_.rd_accept;
    pre_count       = rhs_.pre_count;
    cycle_id        = rhs_.cycle_id;
    sample_time     = rhs_.sample_time;
  endfunction

  // Compares the request and the observed response
  virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
    fifo_sequence_item rhs_;
    if (!$cast(rhs_, rhs)) return 0;
    return super.do_compare(rhs, comparer) &&
           rst == rhs_.rst && wr_en == rhs_.wr_en && rd_en == rhs_.rd_en &&
           data_in == rhs_.data_in && data_out == rhs_.data_out &&
           full == rhs_.full && empty == rhs_.empty &&
           almost_full == rhs_.almost_full && almost_empty == rhs_.almost_empty;
  endfunction

endclass : fifo_sequence_item

`endif // FIFO_SEQUENCE_ITEM_SV
