#!/usr/bin/env python3
# Bridge the CF_owire_id power stubs to the same-net met1 rails.
#
# The stubs are fixed by the placeholder contract: VPWR met1 at x 0..2,
# y 228..229.5; VGND met1 at x 0..2, y 232.5..234. The standard-cell rails
# run from x 4.14 at row boundaries 2.72*k: VGND on even k (228.48, 233.92),
# VPWR on odd k (231.2, 225.76). The VPWR stub therefore sits on a VGND
# rail's row and no same-net rail reaches it. The bridge is:
#   VPWR: vertical met1 x 1.0..2.0, y 228.0..231.44, then horizontal met1
#         x 1.0..4.4, y 230.96..231.44 (meets the VPWR rail at 231.2)
#   VGND: horizontal met1 x 1.0..4.4, y 233.68..234.16 (meets the VGND rail
#         at 233.92)
# The rails start at x 4.14, so the bridge overlaps them by 0.26 um.
# The script refuses to run if the stub geometry differs from the contract.
from reader import click_odb, click
import odb

STUBS = {
    "VPWR": (0.0, 228.0, 2.0, 229.5),
    "VGND": (0.0, 232.5, 2.0, 234.0),
}
BRIDGES = {
    "VPWR": [(1.0, 228.0, 2.0, 231.44), (1.0, 230.96, 4.4, 231.44)],
    "VGND": [(1.0, 233.68, 4.4, 234.16)],
}


@click.command()
@click_odb
def power_stub_bridge(reader):
    block = reader.block
    tech = block.getDataBase().getTech()
    met1 = tech.findLayer("met1")
    dbu = block.getDbUnitsPerMicron()

    def um(v):
        return int(round(v * dbu))

    for net_name, boxes in BRIDGES.items():
        net = block.findNet(net_name)
        if net is None:
            raise SystemExit(f"[power_stub_bridge] net {net_name} missing")
        bterm = block.findBTerm(net_name)
        if bterm is None:
            raise SystemExit(f"[power_stub_bridge] pin {net_name} missing")
        found = []
        for bpin in bterm.getBPins():
            for box in bpin.getBoxes():
                found.append((
                    box.getTechLayer().getName(),
                    box.xMin() / dbu, box.yMin() / dbu,
                    box.xMax() / dbu, box.yMax() / dbu,
                ))
        want = ("met1",) + STUBS[net_name]
        if len(found) != 1 or any(
            f[0] != want[0] or any(abs(a - b) > 1e-3 for a, b in zip(f[1:], want[1:]))
            for f in found
        ):
            raise SystemExit(
                f"[power_stub_bridge] {net_name} stub {found} != contract {want}"
            )
        net.setSpecial()
        swire = odb.dbSWire.create(net, "ROUTED")
        for x0, y0, x1, y1 in boxes:
            odb.dbSBox.create(swire, met1, um(x0), um(y0), um(x1), um(y1), "STRIPE")
    print(
        f"[power_stub_bridge] drew {sum(len(b) for b in BRIDGES.values())} "
        f"met1 bridges for {', '.join(BRIDGES)}"
    )


if __name__ == "__main__":
    power_stub_bridge()
