//------------------------------------------------------------------------------
// File        : fifo_base_sequence.sv
// Description : Base class for all FIFO sequences.
//
//   num_items : number of items (clock cycles) the sequence produces
//   send()    : late randomization - the item is created and randomized after
//               start_item() returns (random data with corner bias), then the
//               control fields are pinned to the requested operation.
//------------------------------------------------------------------------------
`ifndef FIFO_BASE_SEQUENCE_SV
`define FIFO_BASE_SEQUENCE_SV

class fifo_base_sequence extends uvm_sequence #(fifo_sequence_item);

  `uvm_object_utils(fifo_base_sequence)

  int unsigned num_items = 1;

  function new(string name = "fifo_base_sequence");
    super.new(name);
  endfunction

  protected task send(bit rst, bit wr_en, bit rd_en,
                      bit use_data = 1'b0, data_t data = '0);
    fifo_sequence_item item = fifo_sequence_item::type_id::create("item");
    start_item(item);
    if (item.randomize() == 0) `uvm_fatal("RAND", "fifo_sequence_item randomize() failed")
    item.rst   = rst;
    item.wr_en = wr_en;
    item.rd_en = rd_en;
    if (use_data) item.data_in = data;
    finish_item(item);
  endtask

  virtual task body();
    `uvm_warning(get_type_name(), "fifo_base_sequence has no body; use a derived sequence")
  endtask

endclass : fifo_base_sequence

`endif // FIFO_BASE_SEQUENCE_SV
