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
// Module: CF_owire_id_mux
//
// Pad mux for a harness that publishes mask_rev on one GPIO while that
// chip is held in reset, and returns the pin to the user afterwards.
//
//   chip_reset_n = 0:
//     The pad is forced to open-drain (sky130 dm=010, oeb=0, input
//     buffer on) and CF_owire_id drives it. The slave itself is NOT held
//     in reset: its rst_n is the inverse of chip_reset_n, so a 1-Wire
//     master can read the ROM for as long as the external reset is held.
//
//   chip_reset_n = 1:
//     Every pad control passes through from the user ports. The slave is
//     held in reset, so user traffic on the pin cannot arm a transaction
//     that would fire the next time reset is asserted.
//
// A POR pulse is the wrong select. Read ROM takes several milliseconds
// and POR deasserts itself. The tester holds chip_reset_n low for the
// whole transaction, then releases it.
//=============================================================================

`default_nettype none

module CF_owire_id_mux #(
    parameter [7:0]  FAMILY_CODE        = 8'hCF,
    parameter [15:0] SERIAL_HIGH        = 16'hCF1D,
    parameter integer OSC_CYCLES_PER_US = 100,
    parameter integer T_RESET_MIN_US    = 480,
    parameter integer T_PRES_DELAY_US   = 15,
    parameter integer T_PRES_LOW_US     = 120,
    parameter integer T_SAMPLE_US       = 30,
    parameter integer T_READ_LOW_US     = 30
)(
    // Active-low chip reset, e.g. resetb_l. This is the mux select.
    // It is not the slave's reset: the slave runs while this is low.
    input  wire        chip_reset_n,
    input  wire [31:0] mask_rev,

    // User pad controls. Used only while chip_reset_n is high.
    input  wire        gpio_out_user,
    input  wire        gpio_oeb_user,
    input  wire        gpio_inp_dis_user,
    input  wire        gpio_dm2_user,
    input  wire        gpio_dm1_user,
    input  wire        gpio_dm0_user,
    input  wire        gpio_analog_en_user,
    input  wire        gpio_analog_sel_user,
    input  wire        gpio_analog_pol_user,
    input  wire        gpio_ib_mode_sel_user,
    input  wire        gpio_vtrip_sel_user,
    input  wire        gpio_slow_sel_user,
    input  wire        gpio_holdover_user,

    // Pad pin. gpio_in_pin is the pad input buffer.
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
    output wire        gpio_holdover_pin,

    output wire        ip_busy
);

    // Slave runs only while the chip is held in reset.
    wire id_rst_n = ~chip_reset_n;
    wire owire_oeb;

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
        .rst_n     (id_rst_n),
        .id_in     (mask_rev),
        .owire_in  (gpio_in_pin),
        .owire_oeb (owire_oeb),
        .busy      (ip_busy)
    );

    // ID mode: dm=010 (strong-0 / weak-1). gpio_out 1 releases, 0 drives low.
    wire id_mode = ~chip_reset_n;

    assign gpio_out_pin         = id_mode ? owire_oeb          : gpio_out_user;
    assign gpio_oeb_pin         = id_mode ? 1'b0               : gpio_oeb_user;
    assign gpio_inp_dis_pin     = id_mode ? 1'b0               : gpio_inp_dis_user;
    assign gpio_dm2_pin         = id_mode ? 1'b0               : gpio_dm2_user;
    assign gpio_dm1_pin         = id_mode ? 1'b1               : gpio_dm1_user;
    assign gpio_dm0_pin         = id_mode ? 1'b0               : gpio_dm0_user;
    assign gpio_analog_en_pin   = id_mode ? 1'b0               : gpio_analog_en_user;
    assign gpio_analog_sel_pin  = id_mode ? 1'b0               : gpio_analog_sel_user;
    assign gpio_analog_pol_pin  = id_mode ? 1'b0               : gpio_analog_pol_user;
    assign gpio_ib_mode_sel_pin = id_mode ? 1'b0               : gpio_ib_mode_sel_user;
    assign gpio_vtrip_sel_pin   = id_mode ? 1'b0               : gpio_vtrip_sel_user;
    assign gpio_slow_sel_pin    = id_mode ? 1'b0               : gpio_slow_sel_user;
    assign gpio_holdover_pin    = id_mode ? 1'b0               : gpio_holdover_user;

endmodule

`default_nettype wire
