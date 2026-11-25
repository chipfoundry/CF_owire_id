#!/usr/bin/env python3
"""Write pin_template.def: the placeholder CF_owire_id pin contract as DEF.

The hardened macro must keep the placeholder's pin names, layers, directions
and rectangles exactly, so the GDS merge at tapeout can replace the
placeholder cell. The flow reads this template through FP_DEF_TEMPLATE
(as the harness does for the wrapper pins) so the pins are placed at these
coordinates rather than by the pin placer.

The pin list below is a copy of ip/CF_owire_id/build_abstract.py pins() in the
harness. macro/check_pins.py compares the hardened LEF against the placeholder
LEF so any drift is caught.
"""

import os

W_UM = 155.0
H_UM = 240.0
PIN_DEPTH_UM = 2.0
PIN_W_UM = 0.30
PAIR_PITCH_UM = 6.0
PAIR_GAP_UM = 1.20
PAIR_Y0_UM = 8.0
SINGLE_Y0_UM = 90.0
SINGLE_PITCH_UM = 4.0
DBU = 1000

CTRLS = (
    "gpio_out", "gpio_oeb", "gpio_inp_dis", "gpio_ib_mode_sel", "gpio_vtrip_sel",
    "gpio_slow_sel", "gpio_holdover", "gpio_analog_en", "gpio_analog_sel",
    "gpio_analog_pol", "gpio_dm0", "gpio_dm1", "gpio_dm2",
)


def _pair_ys(i):
    user_y = PAIR_Y0_UM + i * PAIR_PITCH_UM
    pad_y = user_y + PAIR_GAP_UM + PIN_W_UM
    return user_y, pad_y


def pins():
    """(name, direction, use, layer, x1, y1, x2, y2) in microns."""
    out = []
    for i, sig in enumerate(CTRLS):
        user_y, pad_y = _pair_ys(i)
        out.append((f"{sig}_user", "INPUT", "SIGNAL", "met3",
                    0.0, user_y, PIN_DEPTH_UM, user_y + PIN_W_UM))
        out.append((f"{sig}_pin", "OUTPUT", "SIGNAL", "met3",
                    0.0, pad_y, PIN_DEPTH_UM, pad_y + PIN_W_UM))
    singles = ["chip_reset_n", "gpio_in_pin"] + [f"mask_rev[{i}]" for i in range(32)]
    for k, name in enumerate(singles):
        y = SINGLE_Y0_UM + k * SINGLE_PITCH_UM
        out.append((name, "INPUT", "SIGNAL", "met3",
                    0.0, y, PIN_DEPTH_UM, y + PIN_W_UM))
    out.append(("VPWR", "INOUT", "POWER", "met1", 0.0, 228.0, PIN_DEPTH_UM, 229.5))
    out.append(("VGND", "INOUT", "GROUND", "met1", 0.0, 232.5, PIN_DEPTH_UM, 234.0))
    return out


def _d(v):
    return int(round(v * DBU))


def write_def(path):
    plist = pins()
    lines = [
        "VERSION 5.8 ;",
        'DIVIDERCHAR "/" ;',
        'BUSBITCHARS "[]" ;',
        "DESIGN CF_owire_id ;",
        f"UNITS DISTANCE MICRONS {DBU} ;",
        f"DIEAREA ( 0 0 ) ( {_d(W_UM)} {_d(H_UM)} ) ;",
        f"PINS {len(plist)} ;",
    ]
    for name, direction, use, layer, x1, y1, x2, y2 in plist:
        # Escape the bus bit brackets the same way the wrapper template does
        # (net name is the pin name).
        lines.append(
            f"- {name} + NET {name} + DIRECTION {direction} + USE {use}\n"
            f"  + LAYER {layer} ( {_d(x1)} {_d(y1)} ) ( {_d(x2)} {_d(y2)} )"
            f" + PLACED ( 0 0 ) N ;"
        )
    lines += ["END PINS", "END DESIGN", ""]
    with open(path, "w") as fh:
        fh.write("\n".join(lines))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    write_def(os.path.join(here, "pin_template.def"))
    print(f"wrote {len(pins())} pins")
