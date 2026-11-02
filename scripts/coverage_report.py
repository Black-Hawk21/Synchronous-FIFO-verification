#!/usr/bin/env python3
"""Merge the functional-coverage tables printed by fifo_coverage into one
report per configuration.

Every test log contains the coverage table and the list of never-hit bins
printed by the coverage collector. A bin counts as covered for a
configuration if at least one run of that configuration hit it, i.e. the
merged uncovered set is the intersection of the per-run uncovered sets.

Usage:  coverage_report.py <regression_dir>
        (expects <regression_dir>/logs/<config>/<test>__seed<N>.log)
Prints a Markdown report on stdout.
"""
import re
import sys
from pathlib import Path

ROW = re.compile(r"^\s+(\S+)\s+(\d+)\s+/\s+(\d+)\s+bins\s+([\d.]+) %")
UNCOVERED_HDR = re.compile(r"^\s+Uncovered bins:\s*(none)?\s*$")
UNCOVERED_BIN = re.compile(r"^\s{4}(\S+) : (.+?)\s*$")
RESET_GROUP = "cp_reset_occupancy"


def parse_log(path):
    """Return (group -> total bins, set of uncovered (group, bin)) or None."""
    totals, uncovered, in_list = {}, set(), False
    for line in path.read_text(errors="replace").splitlines():
        m = ROW.match(line)
        if m:
            totals[m.group(1)] = int(m.group(3))
            continue
        m = UNCOVERED_HDR.match(line)
        if m:
            in_list = m.group(1) is None
            continue
        if in_list:
            m = UNCOVERED_BIN.match(line)
            if m:
                uncovered.add((m.group(1), m.group(2)))
            else:
                in_list = False
    return (totals, uncovered) if totals else None


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    logdir = Path(sys.argv[1]) / "logs"
    configs = sorted(p for p in logdir.iterdir() if p.is_dir()) if logdir.is_dir() else []
    if not configs:
        sys.exit(f"no logs under {logdir}")

    print("| Config | Runs | fifo_cg bins | fifo_cg coverage | incl. reset bins | Never hit |")
    print("|---|---|---|---|---|---|")
    for cfg in configs:
        totals, merged, runs = {}, None, 0
        for log in sorted(cfg.glob("*.log")):
            parsed = parse_log(log)
            if parsed is None:
                continue
            runs += 1
            t, unc = parsed
            totals.update(t)
            merged = unc if merged is None else (merged & unc)
        if runs == 0:
            continue

        def pct(groups):
            vals = [100.0 * (totals[g] - sum(1 for (gg, _) in merged if gg == g)) / totals[g]
                    for g in groups]
            return sum(vals) / len(vals)

        cg_groups = [g for g in totals if g != RESET_GROUP]
        cg_bins = sum(totals[g] for g in cg_groups)
        cg_hit = cg_bins - sum(1 for (g, _) in merged if g != RESET_GROUP)
        never = ", ".join(f"{g}:{b}" for g, b in sorted(merged)) or "none"
        print(f"| {cfg.name} | {runs} | {cg_hit}/{cg_bins} | {pct(cg_groups):.2f} % "
              f"| {pct(list(totals)):.2f} % | {never} |")

    print()
    print("Coverage is the mean of the per-coverpoint/cross percentages "
          "(covergroup default weighting), merged over all runs of each configuration.")


if __name__ == "__main__":
    main()
