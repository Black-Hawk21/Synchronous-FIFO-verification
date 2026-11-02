//------------------------------------------------------------------------------
// File        : fifo_coverage.sv
// Description : Functional coverage collector (uvm_subscriber) connected to
//               the monitor's analysis port.
//
// Same coverage model as sv_tb/fifo_coverage.sv:
//   1. Covergroups fifo_cg / fifo_reset_cg (simulator coverage database).
//   2. A bin tracker with identical bins that prints the coverage table and
//      the never-hit bins in the log on any simulator.
//
// Occupancy is the value before the clock edge (reconstructed by the monitor).
//------------------------------------------------------------------------------
`ifndef FIFO_COVERAGE_SV
`define FIFO_COVERAGE_SV

class fifo_coverage extends uvm_subscriber #(fifo_sequence_item);

  `uvm_component_utils(fifo_coverage)

  int unsigned num_sampled;

  //----------------------------------------------------------------------------
  // Covergroups
  //----------------------------------------------------------------------------
  covergroup fifo_cg with function sample(fifo_sequence_item t);
    option.per_instance = 1;

    cp_wr_en        : coverpoint t.wr_en;
    cp_rd_en        : coverpoint t.rd_en;

    cp_occupancy    : coverpoint t.pre_count {
      bins empty  = {0};
      bins low    = {[1 : OCC_LOW_MAX]};
      bins middle = {[OCC_LOW_MAX + 1 : OCC_HIGH_MIN - 1]};
      bins high   = {[OCC_HIGH_MIN : DEPTH - 1]};
      bins full   = {DEPTH};
    }

    cp_full         : coverpoint t.pre_full;
    cp_empty        : coverpoint t.pre_empty;

    cp_simultaneous : coverpoint (t.wr_en && t.rd_en) {
      bins no  = {1'b0};
      bins yes = {1'b1};
    }

    cp_wr_accept    : coverpoint t.wr_accept;
    cp_rd_accept    : coverpoint t.rd_accept;
    cp_almost_full  : coverpoint t.almost_full;
    cp_almost_empty : coverpoint t.almost_empty;

    cp_status       : coverpoint {t.pre_full, t.pre_empty} {
      bins partial = {2'b00};
      bins empty   = {2'b01};
      bins full    = {2'b10};
      illegal_bins full_and_empty = {2'b11};
    }

    cp_op           : coverpoint {t.wr_en, t.rd_en} {
      bins idle       = {2'b00};
      bins read       = {2'b01};
      bins write      = {2'b10};
      bins write_read = {2'b11};
    }

    cp_data         : coverpoint t.data_in iff (t.wr_accept) {
      bins zero     = {0};
      bins all_ones = {DATA_MAX};
      bins other    = {[1 : DATA_MAX - 1]};
    }

    x_rd_wr         : cross cp_rd_en,     cp_wr_en;
    x_occ_wr        : cross cp_occupancy, cp_wr_en;
    x_occ_rd        : cross cp_occupancy, cp_rd_en;
    x_accept        : cross cp_rd_accept, cp_wr_accept;
    x_status_op     : cross cp_status,    cp_op;
  endgroup

  // Reset arriving with the FIFO empty, partially filled, or full
  covergroup fifo_reset_cg with function sample(fifo_sequence_item t);
    option.per_instance = 1;
    cp_reset_occupancy : coverpoint t.pre_count {
      bins empty   = {0};
      bins partial = {[1 : DEPTH - 1]};
      bins full    = {DEPTH};
    }
  endgroup

  //----------------------------------------------------------------------------
  // Bin tracker (same bins as above)
  //----------------------------------------------------------------------------
  local int unsigned hits[string];
  local string       bin_group[$];
  local string       bin_name[$];
  local string       group_order[$];
  local int unsigned num_unexpected;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    fifo_cg       = new();
    fifo_reset_cg = new();
    define_bins();
  endfunction

  // Analysis port callback: one call per observed cycle
  function void write(fifo_sequence_item t);
    sample(t);
  endfunction

  function void sample(fifo_sequence_item t);
    string occ  = occ_bin(t.pre_count);
    string stat = status_bin(t.pre_full, t.pre_empty);
    string op   = op_bin(t.wr_en, t.rd_en);

    num_sampled++;

    if (t.rst) begin
      fifo_reset_cg.sample(t);
      hit("cp_reset_occupancy", (t.pre_count == 0)     ? "empty" :
                                (t.pre_count >= DEPTH) ? "full"  : "partial");
      return;
    end

    fifo_cg.sample(t);

    hit("cp_wr_en",        $sformatf("%0b", t.wr_en));
    hit("cp_rd_en",        $sformatf("%0b", t.rd_en));
    hit("cp_occupancy",    occ);
    hit("cp_full",         $sformatf("%0b", t.pre_full));
    hit("cp_empty",        $sformatf("%0b", t.pre_empty));
    hit("cp_simultaneous", (t.wr_en && t.rd_en) ? "yes" : "no");
    hit("cp_wr_accept",    $sformatf("%0b", t.wr_accept));
    hit("cp_rd_accept",    $sformatf("%0b", t.rd_accept));
    hit("cp_almost_full",  $sformatf("%0b", t.almost_full));
    hit("cp_almost_empty", $sformatf("%0b", t.almost_empty));
    hit("cp_status",       stat);
    hit("cp_op",           op);
    if (t.wr_accept)
      hit("cp_data", (t.data_in == 0)        ? "zero"     :
                     (t.data_in == DATA_MAX) ? "all_ones" : "other");

    hit("x_rd_wr",     $sformatf("rd=%0b,wr=%0b", t.rd_en, t.wr_en));
    hit("x_occ_wr",    $sformatf("%s,wr=%0b", occ, t.wr_en));
    hit("x_occ_rd",    $sformatf("%s,rd=%0b", occ, t.rd_en));
    hit("x_accept",    $sformatf("rd_acc=%0b,wr_acc=%0b", t.rd_accept, t.wr_accept));
    hit("x_status_op", $sformatf("%s,%s", stat, op));
  endfunction

  //----------------------------------------------------------------------------
  // Bin naming (mirrors the covergroup bins)
  //----------------------------------------------------------------------------
  static function string occ_bin(int unsigned count);
    if (count == 0)            return "empty";
    if (count <= OCC_LOW_MAX)  return "low";
    if (count <  OCC_HIGH_MIN) return "middle";
    if (count <  DEPTH)        return "high";
    if (count == DEPTH)        return "full";
    return "out_of_range";
  endfunction

  static function string status_bin(bit pre_full, bit pre_empty);
    case ({pre_full, pre_empty})
      2'b00:   return "partial";
      2'b01:   return "empty";
      2'b10:   return "full";
      default: return "full_and_empty";   // illegal
    endcase
  endfunction

  static function string op_bin(bit wr_en, bit rd_en);
    case ({wr_en, rd_en})
      2'b00:   return "idle";
      2'b01:   return "read";
      2'b10:   return "write";
      default: return "write_read";
    endcase
  endfunction

  local function void define_bins();
    string occ_bins[5]  = '{"empty", "low", "middle", "high", "full"};
    string stat_bins[3] = '{"partial", "empty", "full"};
    string op_bins[4]   = '{"idle", "read", "write", "write_read"};
    string bit_cps[8]   = '{"cp_wr_en", "cp_rd_en", "cp_full", "cp_empty",
                            "cp_wr_accept", "cp_rd_accept",
                            "cp_almost_full", "cp_almost_empty"};

    foreach (bit_cps[i]) begin
      define_bin(bit_cps[i], "0");
      define_bin(bit_cps[i], "1");
    end
    foreach (occ_bins[i]) define_bin("cp_occupancy", occ_bins[i]);
    define_bin("cp_simultaneous", "no");
    define_bin("cp_simultaneous", "yes");
    foreach (stat_bins[i]) define_bin("cp_status", stat_bins[i]);
    foreach (op_bins[i])   define_bin("cp_op", op_bins[i]);
    define_bin("cp_data", "zero");
    define_bin("cp_data", "all_ones");
    define_bin("cp_data", "other");

    for (int rd = 0; rd < 2; rd++)
      for (int wr = 0; wr < 2; wr++) begin
        define_bin("x_rd_wr",  $sformatf("rd=%0d,wr=%0d", rd, wr));
        define_bin("x_accept", $sformatf("rd_acc=%0d,wr_acc=%0d", rd, wr));
      end
    foreach (occ_bins[i])
      for (int b = 0; b < 2; b++) begin
        define_bin("x_occ_wr", $sformatf("%s,wr=%0d", occ_bins[i], b));
        define_bin("x_occ_rd", $sformatf("%s,rd=%0d", occ_bins[i], b));
      end
    foreach (stat_bins[i])
      foreach (op_bins[j])
        define_bin("x_status_op", $sformatf("%s,%s", stat_bins[i], op_bins[j]));

    define_bin("cp_reset_occupancy", "empty");
    define_bin("cp_reset_occupancy", "partial");
    define_bin("cp_reset_occupancy", "full");
  endfunction

  local function void define_bin(string group, string name);
    bit known_group = 0;
    foreach (group_order[i]) if (group_order[i] == group) known_group = 1;
    if (!known_group) group_order.push_back(group);
    bin_group.push_back(group);
    bin_name.push_back(name);
    hits[{group, ":", name}] = 0;
  endfunction

  local function void hit(string group, string name);
    string key = {group, ":", name};
    if (hits.exists(key)) hits[key]++;
    else                  num_unexpected++;   // e.g. "full_and_empty"
  endfunction

  //----------------------------------------------------------------------------
  // Results
  //----------------------------------------------------------------------------
  // Mean of the per-coverpoint/cross percentages (the default covergroup
  // weighting: every coverpoint and cross has weight 1).
  function real tracker_coverage(bit include_reset_group = 1);
    real sum = 0.0;
    int  n   = 0;
    foreach (group_order[g]) begin
      if (!include_reset_group && group_order[g] == "cp_reset_occupancy") continue;
      sum += group_coverage(group_order[g]);
      n++;
    end
    return (n == 0) ? 0.0 : sum / real'(n);
  endfunction

  function real group_coverage(string group);
    int total = 0;
    int hit_n = 0;
    foreach (bin_group[i]) begin
      if (bin_group[i] != group) continue;
      total++;
      if (hits[{group, ":", bin_name[i]}] > 0) hit_n++;
    end
    return (total == 0) ? 0.0 : 100.0 * real'(hit_n) / real'(total);
  endfunction

  function void report_phase(uvm_phase phase);
    string s;
    int uncovered = 0;
    s = {s, "\n", "---------------------------------------------------------------"};
    s = {s, "\n", $sformatf(" Functional coverage (%0d samples)", num_sampled)};
    s = {s, "\n", "---------------------------------------------------------------"};
`ifndef VERILATOR
    s = {s, "\n", $sformatf("  covergroup fifo_cg        : %6.2f %%", fifo_cg.get_inst_coverage())};
    s = {s, "\n", $sformatf("  covergroup fifo_reset_cg  : %6.2f %%", fifo_reset_cg.get_inst_coverage())};
`endif
    foreach (group_order[g]) begin
      int total = 0;
      int hit_n = 0;
      foreach (bin_group[i]) begin
        if (bin_group[i] != group_order[g]) continue;
        total++;
        if (hits[{group_order[g], ":", bin_name[i]}] > 0) hit_n++;
      end
      s = {s, "\n", $sformatf("  %-20s %3d / %-3d bins  %6.2f %%", group_order[g],
                               hit_n, total, group_coverage(group_order[g]))};
    end
    s = {s, "\n", $sformatf("  tracker total (fifo_cg bins)        : %6.2f %%", tracker_coverage(0))};
    s = {s, "\n", $sformatf("  tracker total (incl. reset bins)    : %6.2f %%", tracker_coverage(1))};
    foreach (bin_group[i]) begin
      if (hits[{bin_group[i], ":", bin_name[i]}] == 0) begin
        if (uncovered == 0) s = {s, "\n", "  Uncovered bins:"};
        s = {s, "\n", $sformatf("    %s : %s", bin_group[i], bin_name[i])};
        uncovered++;
      end
    end
    if (uncovered == 0) s = {s, "\n", "  Uncovered bins: none"};
    if (num_unexpected != 0)
      s = {s, "\n", $sformatf("  Samples outside every defined bin: %0d", num_unexpected)};
    `uvm_info(get_type_name(), s, UVM_NONE)
  endfunction

endclass : fifo_coverage

`endif // FIFO_COVERAGE_SV
