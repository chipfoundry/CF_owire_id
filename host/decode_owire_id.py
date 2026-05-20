#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 ChipFoundry, a DBA of Umbralogic Technologies LLC
# SPDX-License-Identifier: Apache-2.0

"""
Host-side decoder for the CF_owire_id 64-bit Dallas/Maxim 1-Wire ROM ID
emitted by ChipFoundry OpenFrame chips.

The ROM layout (LSB-first on the wire, MSB-first when a Linux `w1` driver
or a Dallas-style address string reports it) is:

    bits  7:0   family code        (default 0xCF)
    bits 39:8   serial[31:0]       = padframe mask_rev
    bits 55:40  serial[47:32]      = magic (default 0xCF1D)
    bits 63:56  CRC-8              (Dallas 0x8C polynomial over bits 0..55)

The script supports three input modes:

    1. Linux `w1` sysfs scan: enumerate /sys/bus/w1/devices/, decode any
       device whose family byte matches our expected value.

        $ ./decode_owire_id.py --w1

    2. Pre-captured ROM bytes (LSB-first byte order, as the bits actually
       come off the wire).

        $ ./decode_owire_id.py --hex-lsb "CF 78 56 34 12 1D CF 8F"

    3. Dallas display address string (MSB-first, dash-separated -- this is
       how `w1`, `owfs`, and Maxim/Analog Devices datasheets typically
       print 1-Wire IDs).

        $ ./decode_owire_id.py --addr "8F-CF-1D-12-34-56-78-CF"

Exit status is 0 if the decoded CRC matches what the ROM carries, non-zero
otherwise (or if no matching device was found in --w1 mode).
"""

from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass
from pathlib import Path


DEFAULT_FAMILY_CODE = 0xCF
DEFAULT_SERIAL_HIGH = 0xCF1D


def crc8_dallas(data56: int) -> int:
    crc = 0
    for i in range(56):
        bit_in = (data56 >> i) & 1
        fb = (crc & 1) ^ bit_in
        crc = crc >> 1
        if fb:
            crc ^= 0x8C
    return crc & 0xFF


@dataclass
class RomDecoded:
    rom:            int
    rom_bytes_lsb:  list[int]
    family:         int
    serial_low:     int
    serial_high:    int
    crc:            int
    expected_crc:   int

    @property
    def crc_ok(self) -> bool:
        return self.crc == self.expected_crc

    @property
    def family_ok(self) -> bool:
        return self.family == DEFAULT_FAMILY_CODE

    @property
    def serial_high_ok(self) -> bool:
        return self.serial_high == DEFAULT_SERIAL_HIGH


def decode_rom_int(rom: int) -> RomDecoded:
    rom &= (1 << 64) - 1
    rom_bytes = [(rom >> (8 * i)) & 0xFF for i in range(8)]
    family       = rom & 0xFF
    serial_low   = (rom >> 8)  & 0xFFFFFFFF
    serial_high  = (rom >> 40) & 0xFFFF
    crc          = (rom >> 56) & 0xFF
    expected     = crc8_dallas(rom & ((1 << 56) - 1))
    return RomDecoded(rom, rom_bytes, family, serial_low,
                      serial_high, crc, expected)


def parse_hex_lsb(text: str) -> int:
    """Parse `--hex-lsb "CF 78 56 34 12 1D CF 8F"` into a 64-bit int.
    Bytes are in transmit order (LSB byte first)."""
    cleaned = text.replace(",", " ").replace("0x", "").replace("0X", "")
    bytes_ = [int(p, 16) for p in cleaned.split()]
    if len(bytes_) != 8:
        raise ValueError(f"expected 8 hex bytes, got {len(bytes_)}")
    rom = 0
    for i, b in enumerate(bytes_):
        rom |= (b & 0xFF) << (8 * i)
    return rom


def parse_dallas_addr(text: str) -> int:
    """Parse a Dallas display address (e.g. "8F-CF-1D-12-34-56-78-CF") --
    MSB-first byte order -- into the same 64-bit int decode_rom_int uses."""
    cleaned = text.replace(" ", "").replace(",", "")
    parts = [p for p in cleaned.split("-") if p]
    if len(parts) != 8:
        raise ValueError(f"expected 8 hex bytes in dashed format, got {len(parts)}")
    bytes_msb = [int(p, 16) for p in parts]
    rom = 0
    for b in bytes_msb:
        rom = (rom << 8) | (b & 0xFF)
    return rom


def report(d: RomDecoded) -> int:
    rom_lsb_str = " ".join(f"{b:02X}" for b in d.rom_bytes_lsb)
    rom_dallas  = "-".join(f"{b:02X}" for b in reversed(d.rom_bytes_lsb))

    print(f"raw bytes (LSB-first)  : {rom_lsb_str}")
    print(f"Dallas address (MSB)   : {rom_dallas}")
    print(f"64-bit ROM             : 0x{d.rom:016X}")
    print(f"family code            : 0x{d.family:02X}"
          + ("  OK" if d.family_ok
             else f"  unexpected (expected 0x{DEFAULT_FAMILY_CODE:02X})"))
    print(f"serial low (mask_rev)  : 0x{d.serial_low:08X}")
    print(f"serial high (magic)    : 0x{d.serial_high:04X}"
          + ("  OK" if d.serial_high_ok
             else f"  unexpected (expected 0x{DEFAULT_SERIAL_HIGH:04X})"))
    print(f"CRC-8 (RX)             : 0x{d.crc:02X}")
    print(f"CRC-8 (recomputed)     : 0x{d.expected_crc:02X}"
          + ("  OK" if d.crc_ok else "  MISMATCH"))
    return 0 if d.crc_ok else 1


def scan_w1(family_filter: int) -> int:
    base = Path("/sys/bus/w1/devices")
    if not base.exists():
        print(f"ERROR: {base} does not exist. Is the w1 kernel module loaded?",
              file=sys.stderr)
        return 2

    family_prefix = f"{family_filter:02x}-"
    found_any = False
    rc = 0
    for entry in sorted(base.iterdir()):
        name = entry.name
        if not name.startswith(family_prefix):
            continue
        found_any = True
        # `w1` device names are family_lo + serial(48 bits, hex, little-endian
        # display).  Parse them back into our internal MSB-first 64-bit int.
        try:
            family_str, serial_str = name.split("-", 1)
            family = int(family_str, 16)
            serial = int(serial_str, 16)
            # crc-from-driver isn't exposed in the device-name; we'd need to
            # read /sys/bus/w1/devices/<name>/id to get the full 8-byte ROM.
            id_path = entry / "id"
            if id_path.exists():
                id_bytes = id_path.read_bytes()
                if len(id_bytes) == 8:
                    rom = int.from_bytes(id_bytes, "little")
                    d = decode_rom_int(rom)
                    print(f"\n=== {name} ===")
                    rc |= report(d)
                    continue
            print(f"\n=== {name} ===")
            print(f"family={family:02X}  serial={serial:012X}  (no /id available)")
        except Exception as e:  # noqa: BLE001
            print(f"WARN: could not parse {name}: {e}", file=sys.stderr)
            rc = 1

    if not found_any:
        print(f"no /sys/bus/w1/devices entry with family 0x{family_filter:02X}",
              file=sys.stderr)
        return 2
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--w1", action="store_true",
                     help="enumerate Linux /sys/bus/w1/devices/ for CF family")
    src.add_argument("--hex-lsb",
                     help='8 hex bytes, LSB-first transmit order, e.g. "CF 78 56 34 12 1D CF 8F"')
    src.add_argument("--addr",
                     help='Dallas-style address, MSB-first, e.g. "8F-CF-1D-12-34-56-78-CF"')
    ap.add_argument("--family", type=lambda x: int(x, 0),
                    default=DEFAULT_FAMILY_CODE,
                    help=f"family-code filter for --w1 (default 0x{DEFAULT_FAMILY_CODE:02X})")
    args = ap.parse_args()

    if args.w1:
        return scan_w1(args.family)

    if args.hex_lsb:
        rom = parse_hex_lsb(args.hex_lsb)
    else:
        rom = parse_dallas_addr(args.addr)

    return report(decode_rom_int(rom))


if __name__ == "__main__":
    sys.exit(main())
