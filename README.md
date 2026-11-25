# CF_owire_id

**Dallas/Maxim 1-Wire chip-ID slave for ChipFoundry OpenFrame projects.**
Publishes the padframe `mask_rev` as a DS2401-compatible 64-bit ROM ID over a single open-drain GPIO. **No external clock connection is required** — the IP carries its own ring oscillator — which makes it the right ID-readout choice for OpenFrame designs that don't have a clock to spare. Read it with any stock 1-Wire master: a host MCU, an FTDI MPSSE 1-Wire library, an oscilloscope's protocol decoder, or just the Linux `w1` driver with a USB 1-Wire adapter.

Two ways to use it inside `openframe_project_wrapper`:

- **`CF_owire_id_pad`** — give the IP one dedicated open-drain GPIO.
- **`CF_owire_id_shared`** — share the GPIO (e.g. `GPIO[0]`) with your own logic; both the IP and the user can pull the wire low, read the line, and release.

Comes with a self-checking iverilog testbench acting as a real 1-Wire master, a host-side Python decoder, and a worked reference design in `openframe_example.v`.

Apache-2.0.

---

## Table of contents

1. [What it does](#what-it-does)
2. [ROM layout](#rom-layout)
3. [Repository layout](#repository-layout)
4. [Integration](#integration)
   - [`CF_owire_id_pad` — dedicated GPIO](#cf_owire_id_pad--dedicated-gpio)
   - [`CF_owire_id_shared` — shared GPIO](#cf_owire_id_shared--shared-gpio)
   - [`CF_owire_id` — the core, for advanced users](#cf_owire_id--the-core-for-advanced-users)
5. [Parameters & port reference](#parameters--port-reference)
6. [Internal oscillator and synthesis](#internal-oscillator-and-synthesis)
7. [Host-side decoding](#host-side-decoding)
8. [Bench testing the IP](#bench-testing-the-ip)
9. [Common pitfalls](#common-pitfalls)
10. [Reference design](#reference-design)
11. [License](#license)

---

## What it does

OpenFrame chips carry a 32-bit hardcoded `mask_rev` value, programmed via the `user_id_programming` block inside `chip_io_openframe`. In Caravel that value is read back through the housekeeping SPI; OpenFrame has no housekeeping SoC, so the user project has to publish it. `CF_owire_id` does that with the minimum requirements possible on the chip side:

- **one open-drain GPIO** for both directions of the 1-Wire bus,
- **no other connections** (no clock pin, no reset choreography, no host firmware), and
- a **standard, off-the-shelf host protocol** so existing Linux/Arduino/FTDI tooling decodes the chip ID without custom software.

Behaviour at the package pin:

- Idle: chip releases the line (open-drain weak-high; an external pull-up — or the OpenFrame pad's weak-1 driver in `dm=010` mode — holds it high).
- Host's 1-Wire master pulls the line low for ≥ `T_RESET_MIN_US` (480 µs standard): chip detects a reset pulse.
- `T_PRES_DELAY_US` µs (15 µs default) after the master releases, the chip drives the line low for `T_PRES_LOW_US` µs (120 µs default) — the presence pulse.
- The host writes 8 bits of command, LSB-first, using standard 1-Wire write slots:
  - `0x33` (Read ROM) → chip transmits the 64-bit ROM, LSB-first, one bit per master-initiated read slot.
  - Anything else → chip returns to idle.

This is exactly the protocol a DS2401 silicon serial number speaks. Linux's `w1` kernel module, the OWFS userspace stack, and most MCU 1-Wire libraries already know how to read it.

## ROM layout

64 bits, transmitted LSB-first per Dallas 1-Wire convention. The bytes appear in the order they come off the wire below:

| Bits   | Field                | Source                                          |
|-------:|----------------------|-------------------------------------------------|
| `7:0`  | Family code          | `FAMILY_CODE` parameter (default `0xCF`)        |
| `39:8` | Serial low 32 bits   | `mask_rev` (from the padframe `user_id_programming`) |
| `55:40`| Serial high 16 bits  | `SERIAL_HIGH` parameter (default `0xCF1D`)      |
| `63:56`| CRC-8                | Dallas polynomial `0x8C`, over bits 0..55       |

Example: with the defaults and `mask_rev = 0x12345678`, the 8 ROM bytes in transmit order (LSB-first byte order) are:

```
CF 78 56 34 12 1D CF 8F
```

Which a Dallas-style host display would print MSB-first as `8F-CF-1D-12-34-56-78-CF`.

## Repository layout

```
CF_owire_id/
  CF_owire_id.yaml        # IP manifest
  LICENSE                 # Apache 2.0
  README.md               # this file
  filelist.f              # include all RTL with one -f flag

  rtl/
    CF_owire_id.v         # 1-Wire slave core + behavioural / synth osc
    CF_owire_id_pad.v     # OpenFrame pad wrapper -- dedicated GPIO
    CF_owire_id_shared.v  # OpenFrame pad wrapper -- shared GPIO (open-drain co-use)
    CF_owire_id_mux.v     # Pad mux -- ID owns the pin while chip reset is held

  sim/
    tb_CF_owire_id.v      # self-checking iverilog testbench (acts as 1-Wire master)
    tb_CF_owire_id_mux.v  # mux pass-through and reset-held ROM read
    Makefile              # `make sim` / `make vcd` / `make clean`

  host/
    decode_owire_id.py    # Linux w1 / hex / Dallas-address decoder
```

Your OpenFrame synthesis flow only needs the files listed in `filelist.f`. The `sim/` and `host/` directories are for bring-up and bench testing.

## Integration

`CF_owire_id_pad` and `CF_owire_id_shared` are the two ways you'd ever instantiate this IP in a real OpenFrame design. Pick one based on whether the pin you want the ID on is also a pin you need for your own logic.

| Wrapper              | Pad mode                       | Use it when                                            |
|----------------------|--------------------------------|--------------------------------------------------------|
| `CF_owire_id_pad`    | OpenFrame open-drain (`dm=010`) | You can spare one GPIO exclusively for the ID.         |
| `CF_owire_id_shared` | OpenFrame open-drain (`dm=010`) + ownership mux | The ID pin (e.g. `GPIO[0]`) is also a user-facing pin. |
| `CF_owire_id_mux`    | `dm=010` while `chip_reset_n` is low; user pad controls otherwise | The harness reads the ID while the part is held in reset, then the user design owns the pin. |

Both wrappers consume **only one** OpenFrame GPIO. Nothing else on the chip is touched — every other GPIO bit is yours to configure.

### `CF_owire_id_mux` — ID while reset is held

`chip_reset_n` is the mux select, and it is not the slave's reset. While it is low the pad is forced to `dm=010` and the slave runs, so a tester can complete a Read ROM for as long as it holds the chip in reset. When `chip_reset_n` goes high, the user's `gpio_out`, `gpio_oeb`, `gpio_dm`, and the other pad controls connect straight through, and the slave is held in reset so later user traffic cannot arm a transaction.

Hold reset for the whole Read ROM. The transaction takes several milliseconds, and releasing reset mid-read gives the pin back. A POR pulse is not long enough and cannot be stretched by the tester.

### `CF_owire_id_pad` — dedicated GPIO

The simplest integration. Wire it to one GPIO and you're done. Pad mode is locked to `dm=010` open-drain with `oeb=0` and `inp_dis=0`.

```verilog
CF_owire_id_pad #(
    .FAMILY_CODE       (8'hCF),
    .SERIAL_HIGH       (16'hCF1D)
    // Leave the timing parameters at their defaults for real silicon
    // (480 us / 15 us / 120 us / 30 us / 30 us).  See the "Bench testing"
    // section for how to shrink them for simulation.
) u_owire (
    .rst_n                (resetb_l),
    .mask_rev             (mask_rev),

    // The IP owns this one pin (here GPIO[42]):
    .gpio_in_pin          (gpio_in[42]),
    .gpio_out_pin         (gpio_out[42]),
    .gpio_oeb_pin         (gpio_oeb[42]),
    .gpio_inp_dis_pin     (gpio_inp_dis[42]),
    .gpio_dm2_pin         (gpio_dm2[42]),
    .gpio_dm1_pin         (gpio_dm1[42]),
    .gpio_dm0_pin         (gpio_dm0[42]),
    .gpio_analog_en_pin   (gpio_analog_en[42]),
    .gpio_analog_sel_pin  (gpio_analog_sel[42]),
    .gpio_analog_pol_pin  (gpio_analog_pol[42]),
    .gpio_ib_mode_sel_pin (gpio_ib_mode_sel[42]),
    .gpio_vtrip_sel_pin   (gpio_vtrip_sel[42]),
    .gpio_slow_sel_pin    (gpio_slow_sel[42]),
    .gpio_holdover_pin    (gpio_holdover[42])
);
```

The OpenFrame open-drain pad mode (`dm=010`) drives strong-0 / weak-1, so you don't need an external pull-up resistor on the test board if the on-chip weak-1 driver is enough for the bus capacitance. For long cables or heavy parasitics, add a 4.7 kΩ external pull-up to VCCIO.

### `CF_owire_id_shared` — shared GPIO

Use this on `GPIO[0]` (or any other pin you want the ID on AND want user logic on). The pad is permanently in open-drain mode and either side — the IP or the user — can pull the wire low. The line floats high (via the pad's weak-1 driver) when neither side is asserting.

```verilog
wire ip_busy;
wire gpio0_in;
wire my_user_pull_low = my_logic_value;    // 1 = pull the line low, 0 = release

CF_owire_id_shared #(
    .FAMILY_CODE (8'hCF),
    .SERIAL_HIGH (16'hCF1D)
) u_owire_shared (
    .rst_n                (resetb_l),
    .mask_rev             (mask_rev),

    // User-side open-drain port for the shared pin:
    .user_pull_low        (my_user_pull_low),
    .user_in              (gpio0_in),
    .ip_busy              (ip_busy),

    // OpenFrame pad signals for the shared GPIO (here GPIO[0]):
    .gpio_in_pin          (gpio_in[0]),
    .gpio_out_pin         (gpio_out[0]),
    .gpio_oeb_pin         (gpio_oeb[0]),
    .gpio_inp_dis_pin     (gpio_inp_dis[0]),
    .gpio_dm2_pin         (gpio_dm2[0]),
    .gpio_dm1_pin         (gpio_dm1[0]),
    .gpio_dm0_pin         (gpio_dm0[0]),
    .gpio_analog_en_pin   (gpio_analog_en[0]),
    .gpio_analog_sel_pin  (gpio_analog_sel[0]),
    .gpio_analog_pol_pin  (gpio_analog_pol[0]),
    .gpio_ib_mode_sel_pin (gpio_ib_mode_sel[0]),
    .gpio_vtrip_sel_pin   (gpio_vtrip_sel[0]),
    .gpio_slow_sel_pin    (gpio_slow_sel[0]),
    .gpio_holdover_pin    (gpio_holdover[0])
);
```

Sharing rules:

- **Whoever pulls low wins.** The pad drives strong-0 if `user_pull_low=1` OR the IP is asserting low. If neither side asserts, the pad releases and the line floats high.
- **The user can read the line at any time** via `user_in`.
- **The user can't drive *high*.** Open-drain only releases. If you need to assert a high level, use a different GPIO — or know that the line floats high once you stop pulling low.
- **`ip_busy = 1` while the IP is in the middle of a 1-Wire transaction** (presence pulse, command receive, or ROM readout). User FSMs that don't want their pulls interfering with a host master can gate on `!ip_busy`.
- **Constraint:** the user MUST NOT pull the line low continuously for ≥ `T_RESET_MIN_US` (480 µs by default). A sustained low looks identical to a 1-Wire master reset pulse and will wake the slave's FSM. This is irrelevant for typical user uses (LEDs, status bits, button reads, short pulses); be careful if you implement another protocol on the same wire.

### `CF_owire_id` — the core, for advanced users

`CF_owire_id` is the 1-Wire slave underneath both pad wrappers. It's logic-plus-ring-oscillator with no pad config in it. You'd only instantiate it directly if you've built your own pad-config block and want to plug the slave into it.

```verilog
wire owire_oeb;
wire owire_busy;

CF_owire_id #(
    .FAMILY_CODE (8'hCF),
    .SERIAL_HIGH (16'hCF1D)
) u_owire (
    .rst_n     (resetb_l),
    .id_in     (mask_rev),
    .owire_in  (line_value),     // pad input
    .owire_oeb (owire_oeb),      // 0 = drive low, 1 = release
    .busy      (owire_busy)
);
```

You're then on the hook for routing `owire_oeb` and the wire's input through your own open-drain pad config. For 99% of OpenFrame projects, just use `CF_owire_id_pad` or `CF_owire_id_shared` and skip this section.

## Parameters & port reference

### Parameters (all three modules)

| Name                 | Default      | Description                                                  |
|----------------------|--------------|--------------------------------------------------------------|
| `FAMILY_CODE`        | `8'hCF`      | Dallas family-code byte (low 8 bits of ROM).                 |
| `SERIAL_HIGH`        | `16'hCF1D`   | High 16 bits of the 48-bit serial.                           |
| `OSC_CYCLES_PER_US`  | `100`        | Internal oscillator cycles per µs. Scale all timings by changing this. |
| `T_RESET_MIN_US`     | `480`        | Master reset pulse threshold (1-Wire standard).              |
| `T_PRES_DELAY_US`    | `15`         | Delay before presence after master release.                  |
| `T_PRES_LOW_US`      | `120`        | Presence pulse low duration.                                  |
| `T_SAMPLE_US`        | `30`         | Slave sample point inside a master-write slot.               |
| `T_READ_LOW_US`      | `30`         | Slave-write-0 hold during a read slot.                       |

### `CF_owire_id` ports

| Signal      | Dir | Width | Description                                              |
|-------------|-----|-------|----------------------------------------------------------|
| `rst_n`     | in  | 1     | Active-low chip reset. Holds the slave in IDLE.          |
| `id_in`     | in  | 32    | Low 32 bits of the serial. Connect to `mask_rev`.        |
| `owire_in`  | in  | 1     | Bidirectional pad input (line level).                    |
| `owire_oeb` | out | 1     | Bidirectional pad output-enable bar. `0` = drive low, `1` = release. |
| `busy`      | out | 1     | High while the FSM is engaged (anything other than IDLE).|

### Pad wrappers (`CF_owire_id_pad`, `CF_owire_id_shared`)

Both wrappers add a `mask_rev[31:0]` payload input and the 14 OpenFrame GPIO control signals: `gpio_in_pin`, `gpio_out_pin`, `gpio_oeb_pin`, `gpio_inp_dis_pin`, `gpio_dm[2:0]_pin`, `gpio_analog_{en,sel,pol}_pin`, `gpio_ib_mode_sel_pin`, `gpio_vtrip_sel_pin`, `gpio_slow_sel_pin`, `gpio_holdover_pin`.

`CF_owire_id_shared` additionally exposes:

| Signal          | Dir | Description                                              |
|-----------------|-----|----------------------------------------------------------|
| `user_pull_low` | in  | 1 = user is pulling the wire low (wired-OR with the IP). |
| `user_in`       | out | Pad input value. Always valid.                           |
| `ip_busy`       | out | 1 while the IP is engaged in a 1-Wire transaction.       |

## Internal oscillator and synthesis

`CF_owire_id` carries its own clock. The source RTL has three osc implementations behind `\`ifdef` guards:

| Define          | Osc implementation                                | When to use       |
|-----------------|---------------------------------------------------|-------------------|
| `COCOTB_SIM`    | Behavioural `always #5 sim_osc = ~sim_osc;`       | cocotb tests      |
| `IVERILOG_SIM`  | Same behavioural osc                              | this repo's `sim/` |
| `SYNTHESIS`     | Kept sky130 NAND-enabled ring + ripple divide-by-32 | synthesis flow    |
| (none)          | Behavioural osc (fallback)                         | quick experiments |

The `SYNTHESIS` branch is a kept sky130 ring, gated by `rst_n` (the ring only runs while the core is out of reset):

```verilog
(* keep = "true" *) sky130_fd_sc_hd__nand2_1 u_ring_en (.A(rst_n), .B(r4), .Y(r0));
(* keep = "true" *) sky130_fd_sc_hd__inv_1   u_ring_i1 (.A(r0), .Y(r1));
(* keep = "true" *) sky130_fd_sc_hd__inv_1   u_ring_i2 (.A(r1), .Y(r2));
(* keep = "true" *) sky130_fd_sc_hd__inv_1   u_ring_i3 (.A(r2), .Y(r3));
(* keep = "true" *) sky130_fd_sc_hd__inv_1   u_ring_i4 (.A(r3), .Y(r4));
```

A ripple divide-by-32 (`q0`..`q4`, async reset by `rst_n`) brings the ring down to `osc_clk = q4`. The divide ratio assumes the ring runs near 3 GHz; confirm the ring frequency with STA or silicon measurement and adjust the divider length. The number of kept inverter stages and their drive strength set the ring frequency and must be re-verified if the cell library changes.

Tune the ring length, drive strength, and divider length to land `osc_clk` near `OSC_CYCLES_PER_US ≈ 100`. The 1-Wire spec is forgiving: anything within roughly 0.5x–2x of the nominal frequency still works with a stock host master.

## Host-side decoding

You need a real 1-Wire master on the host side to talk to the chip. Three common options, easiest first:

### Linux `w1` kernel module + a USB 1-Wire adapter

Plug a DS9097-style adapter (or any kernel-supported 1-Wire master) into a Linux box. Connect the adapter's data line to the chip's `GPIO[42]` (or wherever you wired the IP). The kernel auto-discovers the device:

```
$ ls /sys/bus/w1/devices/
cf-0000cf1d12345678  w1_bus_master1

$ ./host/decode_owire_id.py --w1
=== cf-0000cf1d12345678 ===
raw bytes (LSB-first)  : CF 78 56 34 12 1D CF 8F
Dallas address (MSB)   : 8F-CF-1D-12-34-56-78-CF
64-bit ROM             : 0x8FCF1D12345678CF
family code            : 0xCF  OK
serial low (mask_rev)  : 0x12345678
serial high (magic)    : 0xCF1D  OK
CRC-8 (RX)             : 0x8F
CRC-8 (recomputed)     : 0x8F  OK
```

### Capture from a logic analyzer or scope

Most logic analyzers (Saleae, DSLogic, etc.) have a 1-Wire protocol decoder built in. Capture a Read-ROM transaction, grab the 8 byte payload, then:

```
$ ./host/decode_owire_id.py --hex-lsb "CF 78 56 34 12 1D CF 8F"
```

Or paste in a Dallas-format address (MSB-first):

```
$ ./host/decode_owire_id.py --addr "8F-CF-1D-12-34-56-78-CF"
```

### Custom embedded master (MCU / FTDI MPSSE)

Any MCU 1-Wire library can issue the standard reset + presence + Read-ROM (`0x33`) + 64-bit shift sequence. Once you have the 8 bytes, feed them to the same `decode_owire_id.py` `--hex-lsb` mode for verification.

Exit status is 0 if the CRC matches, non-zero otherwise — easy to wire into bring-up scripts.

## Bench testing the IP

Two layers of tests:

**1. Block-level (iverilog, no OpenFrame infrastructure)** — `sim/tb_CF_owire_id.v` instantiates the bare `CF_owire_id` core, builds an open-drain wire model, and runs a full Verilog 1-Wire master. It pulses reset, waits for presence, sends `0x33`, clocks 64 read slots, validates the ROM against the expected `mask_rev`. Two back-to-back frames with different `id_in` values prove re-arm across resets.

The DUT's 1-Wire timing parameters are scaled down by ~60x in the testbench (`T_RESET_MIN_US=5` etc.) so the run finishes in ~hundreds of µs of simulated time. The protocol itself is identical to canonical 480/15/120/30/30 µs timings; real silicon uses the defaults.

```
$ cd sim
$ make sim
iverilog -g2012 -Wall -DIVERILOG_SIM -o tb_CF_owire_id.vvp ../rtl/CF_owire_id.v tb_CF_owire_id.v
vvp tb_CF_owire_id.vvp

---- CAFEBABE ----
  raw ROM bytes (LSB-first) : cf be ba fe ca 1d cf 47
  64-bit ROM                : 0x47cf1dcafebabecf
  family code               : 0xcf  (expected 0xcf)
  serial[31:0] = mask_rev   : 0xcafebabe  (expected 0xcafebabe)
  serial[47:32] = magic     : 0xcf1d  (expected 0xcf1d)
  CRC-8 (Dallas 0x8C)       : 0x47  (recomputed 0x47)
  PASS

---- 12345678 ----
  raw ROM bytes (LSB-first) : cf 78 56 34 12 1d cf 8f
  PASS

RESULT: PASS
```

`make vcd` opens the waveform in gtkwave.

**2. Top-level (cocotb, OpenFrame integration)** — `verilog/dv/cocotb/owire_id_test/owire_id_test.py` runs the IP through the full `openframe_project_wrapper`, drives the shared `GPIO[0]` as a 1-Wire master from outside the chip, decodes the 64-bit ROM, and verifies the shared-pin handoff to user logic when the IP is idle. Run with:

```
$ cf verify owire_id_test --sim rtl
```

## Common pitfalls

- **No pull-up on a long-cable test board.** The OpenFrame pad in `dm=010` mode drives strong-0 / weak-1 — good enough for a few cm of board trace, marginal for long cables with significant capacitance. Add a 4.7 kΩ external pull-up to VCCIO if you see slow rising edges that confuse the host master.
- **`OSC_CYCLES_PER_US` way off from 100.** All slot timings derive from this. If your ring osc lands at 50 MHz instead of 100, set `OSC_CYCLES_PER_US=50` to keep the µs-denominated thresholds correct.
- **Shared-pin user logic pulling low for > 480 µs.** That looks identical to a master reset pulse and wakes the slave. Keep user-driven lows well below `T_RESET_MIN_US` unless you actually want to issue a reset pulse.
- **Sustained low from any state resets the slave.** A wire held low for `T_RESET_MIN_US` (even by the slave itself) is treated as a reset pulse in any FSM state. This recovers the slave from a power-up or fault state that would otherwise hold the line low forever.
- **Two 1-Wire devices on the same bus.** This IP implements the Read-ROM (`0x33`) subset only — no Search-ROM, no Match-ROM. It works as the sole slave on its bus. For multi-slave buses (or when you want the chip to share a wire with a real DS24xx), implement the Search-ROM algorithm on top of the current FSM.

## Reference design

The IP is wired up end-to-end in `openframe_user_project/verilog/rtl/openframe_example.v` (this repo). It demonstrates the shared-pin pattern: `CF_owire_id_shared` lives on `GPIO[0]` and the demo's user logic also pulls the same wire low (and reads it back) without breaking 1-Wire transactions.

The cocotb test at `openframe_user_project/verilog/dv/cocotb/owire_id_test/owire_id_test.py` verifies:

- a full Reset + Presence + Read-ROM + 64-bit shift sequence completes on `GPIO[0]`,
- the 64-bit ROM decodes to family `0xCF`, serial high `0xCF1D`, the on-chip `mask_rev`, and a matching CRC-8,
- the shared-pin co-use with user logic works (user can pull low and read while the IP is idle).

That same example is the recommended starting point for any new OpenFrame project that wants the ID on `GPIO[0]` while still using `GPIO[0]` for user logic.

## License

Apache 2.0 — see [LICENSE](LICENSE).
