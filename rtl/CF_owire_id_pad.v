// SPDX-FileCopyrightText: 2026 ChipFoundry, a DBA of Umbralogic Technologies LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// SPDX-License-Identifier: Apache-2.0

//=============================================================================
// Module: CF_owire_id_pad
//
// Drop-in wrapper that bundles a CF_owire_id slave with the per-pin pad
// configuration needed for OpenFrame open-drain operation.  Consumes
// exactly one GPIO (whichever pin you wire to the gpio_* ports below) and
// leaves every other GPIO of the wrapper untouched -- so it composes
// cleanly with the rest of a user project that wants to keep GPIO[0]
// (or any other pin) for its own logic.
//
// Typical use inside an openframe_project_wrapper-style user module:
//
//   CF_owire_id_pad u_owire (
//       .rst_n           (resetb_l),
//       .mask_rev        (mask_rev),
//       .gpio_in_pin     (gpio_in[42]),
//       .gpio_out_pin    (gpio_out_42),
//       .gpio_oeb_pin    (gpio_oeb_42),
//       .gpio_inp_dis_pin(gpio_inp_dis_42),
//       .gpio_dm2_pin    (gpio_dm2_42),
//       .gpio_dm1_pin    (gpio_dm1_42),
//       .gpio_dm0_pin    (gpio_dm0_42),
//       .gpio_analog_en_pin   (gpio_analog_en_42),
//       .gpio_analog_sel_pin  (gpio_analog_sel_42),
//       .gpio_analog_pol_pin  (gpio_analog_pol_42),
//       .gpio_ib_mode_sel_pin (gpio_ib_mode_sel_42),
//       .gpio_vtrip_sel_pin   (gpio_vtrip_sel_42),
//       .gpio_slow_sel_pin    (gpio_slow_sel_42),
//       .gpio_holdover_pin    (gpio_holdover_42)
//   );
//
// where gpio_*_42 are the bit slices the user has pre-declared at the
// top level (commonly `assign gpio_out[42] = gpio_out_42;`).
//=============================================================================

`default_nettype none

module CF_owire_id_pad #(
    parameter [7:0]  FAMILY_CODE        = 8'hCF,
    parameter [15:0] SERIAL_HIGH        = 16'hCF1D,
    parameter integer OSC_CYCLES_PER_US = 100,
    parameter integer T_RESET_MIN_US    = 480,
    parameter integer T_PRES_DELAY_US   = 15,
    parameter integer T_PRES_LOW_US     = 120,
    parameter integer T_SAMPLE_US       = 30,
    parameter integer T_READ_LOW_US     = 30
)(
    input  wire        rst_n,            // active-low chip reset (e.g. resetb_l)
    input  wire [31:0] mask_rev,         // padframe mask revision

    // Pad I/O for the single GPIO this IP owns.  Connect these to the
    // corresponding bits of the wrapper's gpio_* buses.
    input  wire        gpio_in_pin,
    output wire        gpio_out_pin,
    output wire        gpio_oeb_pin,
    output wire        gpio_inp_dis_pin,
    output wire        gpio_dm2_pin,
    output wire        gpio_dm1_pin,
    output wire        gpio_dm0_pin,
    output wire        gpio_analog_en_pin,
    output wire        gpio_analog_sel_pin,
    output wire        gpio_analog_pol_pin,
    output wire        gpio_ib_mode_sel_pin,
    output wire        gpio_vtrip_sel_pin,
    output wire        gpio_slow_sel_pin,
    output wire        gpio_holdover_pin
);

    wire owire_oeb;
    wire owire_busy_unused;

    CF_owire_id #(
        .FAMILY_CODE       (FAMILY_CODE),
        .SERIAL_HIGH       (SERIAL_HIGH),
        .OSC_CYCLES_PER_US (OSC_CYCLES_PER_US),
        .T_RESET_MIN_US    (T_RESET_MIN_US),
        .T_PRES_DELAY_US   (T_PRES_DELAY_US),
        .T_PRES_LOW_US     (T_PRES_LOW_US),
        .T_SAMPLE_US       (T_SAMPLE_US),
        .T_READ_LOW_US     (T_READ_LOW_US)
    ) u_ip (
        .rst_n     (rst_n),
        .id_in     (mask_rev),
        .owire_in  (gpio_in_pin),
        .owire_oeb (owire_oeb),
        .busy      (owire_busy_unused)
    );

    // Open-drain pad config (sky130 dm=010 = strong-0 / weak-1):
    //   chip wants to assert low -> owire_oeb=0 -> pad drives strong 0
    //   chip wants to release    -> owire_oeb=1 -> pad drives weak 1
    // No external pull-up resistor needed on the test board.
    assign gpio_out_pin         = owire_oeb;
    assign gpio_oeb_pin         = 1'b0;     // pad always actively driving
    assign gpio_inp_dis_pin     = 1'b0;     // input buffer enabled (we read the line)
    assign gpio_dm2_pin         = 1'b0;
    assign gpio_dm1_pin         = 1'b1;
    assign gpio_dm0_pin         = 1'b0;
    assign gpio_analog_en_pin   = 1'b0;
    assign gpio_analog_sel_pin  = 1'b0;
    assign gpio_analog_pol_pin  = 1'b0;
    assign gpio_ib_mode_sel_pin = 1'b0;
    assign gpio_vtrip_sel_pin   = 1'b0;
    assign gpio_slow_sel_pin    = 1'b0;
    assign gpio_holdover_pin    = 1'b0;

endmodule

`default_nettype wire
