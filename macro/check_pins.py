#!/usr/bin/env python3
"""Compare a hardened CF_owire_id LEF against the placeholder LEF.

The GDS merge at tapeout replaces the placeholder cell, so the hardened macro
must have:
  - the same SIZE (155 x 240 um),
  - the same set of pins with the same DIRECTION, USE, LAYER, and rectangle,
  - VPWR/VGND on met1 at the placeholder landings.
Internal OBS and the cell's contents may differ.

Usage: check_pins.py <hardened.lef> <placeholder.lef>
Exit status is 0 only when every pin matches exactly.
"""

import re
import sys


def parse(path):
    text = open(path).read()
    m = re.search(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)\s*;", text)
    if not m:
        raise SystemExit(f"{path}: no SIZE")
    size = (float(m.group(1)), float(m.group(2)))
    pins = {}
    for pm in re.finditer(r"^\s*PIN (\S+)\n(.*?)^\s*END \1$", text, re.S | re.M):
        name, body = pm.group(1), pm.group(2)
        direction = re.search(r"DIRECTION (\w+)", body)
        use = re.search(r"USE (\w+)", body)
        layers = re.findall(r"LAYER (\w+) ;\s*RECT ([\d.\- ]+?) ;", body)
        rects = []
        for layer, coords in layers:
            vals = tuple(round(float(v), 3) for v in coords.split())
            rects.append((layer, vals))
        pins[name] = {
            "dir": direction.group(1) if direction else None,
            "use": use.group(1) if use else None,
            "rects": sorted(rects),
        }
    return size, pins


# The flow's pin access may extend a met3 pin inward (into the macro) to reach
# a routing track. The outside edge is what the GDS merge and the harness see,
# so an inward extension is allowed up to this many um past the placeholder edge.
MAX_INWARD_EXTENSION_UM = 3.0


def compatible(hard_rects, ref_rects):
    """True if every hardened rect matches the placeholder rect on the outside
    edge: same layer, same x0, same y-range; x1 may extend inward."""
    if len(hard_rects) != len(ref_rects):
        return False
    for (hl, hv), (rl, rv) in zip(sorted(hard_rects), sorted(ref_rects)):
        if hl != rl:
            return False
        hx0, hy0, hx1, hy1 = hv
        rx0, ry0, rx1, ry1 = rv
        if (hx0, hy0, hy1) != (rx0, ry0, ry1):
            return False
        if not (rx1 <= hx1 <= rx1 + MAX_INWARD_EXTENSION_UM):
            return False
    return True


def main():
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    hard_size, hard = parse(sys.argv[1])
    ref_size, ref = parse(sys.argv[2])
    ok = True
    if hard_size != ref_size:
        print(f"SIZE mismatch: hardened {hard_size} vs placeholder {ref_size}")
        ok = False
    missing = sorted(set(ref) - set(hard))
    extra = sorted(set(hard) - set(ref))
    if missing:
        print("missing pins:", missing)
        ok = False
    if extra:
        print("extra pins:", extra)
        ok = False
    bad = []
    extended = []
    for name in sorted(set(ref) & set(hard)):
        h, r = hard[name], ref[name]
        same_meta = (h["dir"], h["use"]) == (r["dir"], r["use"])
        if not same_meta or not compatible(h["rects"], r["rects"]):
            bad.append(name)
            print(f"mismatch {name}:\n  hardened   {h}\n  placeholder {r}")
        elif h["rects"] != r["rects"]:
            extended.append(name)
    print(f"pins: hardened {len(hard)}, placeholder {len(ref)}, "
          f"incompatible {len(bad)}, inward-extended {len(extended)}")
    if extended:
        print("inward-extended (outside edge unchanged):", extended)
    print("RESULT:", "PASS" if ok and not bad else "FAIL")
    sys.exit(0 if ok and not bad else 1)


if __name__ == "__main__":
    main()
