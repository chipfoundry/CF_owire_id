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
// Module: CF_owire_id_shared
//
// Drop-in wrapper that bundles a CF_owire_id slave with the per-pin pad
// configuration needed for OpenFrame open-drain operation AND lets the
// user's own logic co-drive the same wire.  Intended for the case where
// the chip's dedicated ID pin (e.g. GPIO[0]) is also a pin the user
// wants to use for their own purposes.
//
// Sharing model -- open-drain co-drive:
//
//   The pad is permanently in open-drain mode (sky130 dm=010 = strong-0
//   / weak-1).  Whoever wants to assert low (chip OR user) drives the
//   pad strong-0; if neither asserts, the pad releases to weak-1.  Both
//   sides can read the resulting wire level via the input buffer.
//
//   * IP   pulls low when responding to a 1-Wire master transaction
//          (presence pulse + ROM read).
//   * User pulls low by setting `user_pull_low = 1`.
//   * Either can read the wire level via `user_in` / the IP's own input.
//
// Constraint: the user MUST NOT pull the wire low for >= T_RESET_MIN_US
// (default 480 us) -- doing so would look identical to a master reset
// pulse and wake the slave FSM.  For 1-Wire-compatible host setups this
// is exactly the protocol; for user logic that just wants to wiggle the
// pin (LED, slow status, button input, etc.) keep low pulses well under
// the reset threshold.  The optional `ip_busy` output flags windows
// when the slave is actively in a transaction so user FSMs can stay off
// the wire if they care.
//=============================================================================

`default_nettype none

module CF_owire_id_shared #(
    parameter [7:0]  FAMILY_CODE        = 8'hCF,
    parameter [15:0] SERIAL_HIGH        = 16'hCF1D,
    parameter integer OSC_CYCLES_PER_US = 100,
    parameter integer T_RESET_MIN_US    = 480,
    parameter integer T_PRES_DELAY_US   = 15,
    parameter integer T_PRES_LOW_US     = 120,
    parameter integer T_SAMPLE_US       = 30,
    parameter integer T_READ_LOW_US     = 30
)(
    input  wire        rst_n,                  // active-low chip reset (e.g. resetb_l)
    input  wire [31:0] mask_rev,               // padframe mask revision

    // User-side open-drain port for the shared GPIO:
    input  wire        user_pull_low,          // 1 = user is pulling the wire low
    output wire        user_in,                // pad input level (always valid)
    output wire        ip_busy,                // 1 while the slave is engaged in a 1-Wire transaction

    // OpenFrame pad signals for the shared GPIO.  Connect each to the
    // corresponding bit of the wrapper's gpio_* buses (e.g. gpio_in[0],
    // gpio_out[0], ...).
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
    wire owire_busy;

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
        .busy      (owire_busy)
    );

    assign ip_busy = owire_busy;
    assign user_in = gpio_in_pin;

    // Open-drain combining:
    //   chip wants to pull low  : owire_oeb = 0
    //   user wants to pull low  : user_pull_low = 1
    //   either of those         : pad drives strong 0
    //   neither                 : pad releases weak 1
    //
    // The sky130 BIDIR pad in dm=010 mode reads gpio_out_pin as the
    // "release" value: 1 = release (weak high), 0 = drive strong low.
    wire release_high = owire_oeb & ~user_pull_low;

    // Open-drain pad config (sky130 dm=010):
    assign gpio_out_pin         = release_high;
    assign gpio_oeb_pin         = 1'b0;     // pad always actively driving
    assign gpio_inp_dis_pin     = 1'b0;     // input buffer enabled (we and the user read the line)
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
