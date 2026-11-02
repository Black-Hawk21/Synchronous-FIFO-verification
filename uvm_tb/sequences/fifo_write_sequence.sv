//------------------------------------------------------------------------------
// File        : fifo_write_sequence.sv
// Description : num_items consecutive writes. Data is random (corner-biased)
//               unless use_pattern is set, in which case the values are
//               first_value, first_value+1, ...; or use 'values' for an
//               explicit list. Writes are issued even if the FIFO is full.
//------------------------------------------------------------------------------
`ifndef FIFO_WRITE_SEQUENCE_SV
`define FIFO_WRITE_SEQUENCE_SV

class fifo_write_sequence extends fifo_base_sequence;

  `uvm_object_utils(fifo_write_sequence)

  bit    use_pattern = 1'b0;
  data_t first_value = '0;
  data_t values[$];            // if not empty: write exactly these values

  function new(string name = "fifo_write_sequence");
    super.new(name);
  endfunction

  virtual task body();
    if (values.size() != 0) begin
      foreach (values[i]) send(1'b0, 1'b1, 1'b0, 1'b1, values[i]);
    end else begin
      for (int unsigned i = 0; i < num_items; i++)
        send(1'b0, 1'b1, 1'b0, use_pattern, first_value + data_t'(i));
    end
  endtask

endclass : fifo_write_sequence

`endif // FIFO_WRITE_SEQUENCE_SV
