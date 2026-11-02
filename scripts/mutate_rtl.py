#!/usr/bin/env python3
"""Create mutated copies of rtl/sync_fifo.sv for mutation testing.

Each mutant injects one realistic bug with an exact text replacement. A
mutant is "killed" when at least one test fails on it; a good testbench kills
every mutant that changes observable behaviour.

Usage:
  mutate_rtl.py list                      print "name<TAB>description" lines
  mutate_rtl.py make <rtl> <outdir>       write <outdir>/<name>/sync_fifo.sv
"""
import sys
from pathlib import Path

# name, description, original text, replacement text
MUTANTS = [
    ("write_when_full",
     "write accepted while full (overflow corrupts data)",
     "assign wr_accept = wr_en && !full;",
     "assign wr_accept = wr_en;"),
    ("read_when_empty",
     "read accepted while empty (underflow moves rd_ptr)",
     "assign rd_accept = rd_en && !empty;",
     "assign rd_accept = rd_en;"),
    ("write_priority_when_full",
     "simultaneous read+write while full also performs the write",
     "assign wr_accept = wr_en && !full;",
     "assign wr_accept = wr_en && (!full || rd_en);"),
    ("rd_ptr_no_wrap",
     "read pointer relies on natural overflow instead of explicit wrap",
     "if (rd_ptr == PTR_LAST) rd_ptr_next = '0;",
     "if (1'b0)               rd_ptr_next = '0;"),
    ("wr_ptr_wraps_early",
     "write pointer wraps at DEPTH-2 instead of DEPTH-1",
     "if (wr_ptr == PTR_LAST) wr_ptr_next = '0;",
     "if (wr_ptr == PTR_LAST - 1'b1) wr_ptr_next = '0;"),
    ("data_out_not_held",
     "data_out reloads every cycle instead of only on accepted reads",
     "      if (rd_accept) begin\n        data_out <= mem[rd_ptr];",
     "      if (1'b1) begin\n        data_out <= mem[rd_ptr];"),
    ("full_one_early",
     "full asserted at DEPTH-1 entries",
     "assign full         = (count == CNT_FULL);",
     "assign full         = (count == CNT_FULL - 1'b1);"),
    ("almost_full_off_by_one",
     "almost_full uses > instead of >=",
     "assign almost_full  = (count >= CNT_AF);",
     "assign almost_full  = (count > CNT_AF);"),
    ("almost_empty_off_by_one",
     "almost_empty uses < instead of <=",
     "assign almost_empty = (count <= CNT_AE);",
     "assign almost_empty = (count < CNT_AE);"),
    ("count_wrong_on_simultaneous",
     "occupancy increments when a read and a write are both accepted",
     "default: count_next = count;          // both, or neither",
     "default: count_next = count + {{(CNT_W-1){1'b0}}, wr_accept};"),
    ("reset_keeps_data_out",
     "reset does not clear data_out",
     "      count    <= '0;\n      data_out <= '0;",
     "      count    <= '0;"),
    ("read_returns_newest",
     "read returns the entry at the write pointer side (LIFO-like)",
     "data_out <= mem[rd_ptr];",
     "data_out <= mem[(wr_ptr == '0) ? PTR_LAST : wr_ptr - 1'b1];"),
]


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "list":
        for name, desc, _, _ in MUTANTS:
            print(f"{name}\t{desc}")
        return
    if len(sys.argv) == 4 and sys.argv[1] == "make":
        src = Path(sys.argv[2]).read_text()
        out = Path(sys.argv[3])
        for name, _, old, new in MUTANTS:
            if src.count(old) != 1:
                sys.exit(f"mutant {name}: original text found {src.count(old)} times (expected 1)")
            d = out / name
            d.mkdir(parents=True, exist_ok=True)
            (d / "sync_fifo.sv").write_text(src.replace(old, new))
        return
    sys.exit(__doc__)


if __name__ == "__main__":
    main()
