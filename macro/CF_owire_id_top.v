// SPDX-FileCopyrightText: 2026 ChipFoundry, a DBA of Umbralogic Technologies LLC
// SPDX-License-Identifier: Apache-2.0
//
// CF_owire_id hardened macro: the placeholder-compatible top.
//
// Drop-in replacement for the CF_owire_id placeholder cell at tapeout. The
// port list, the 155 x 240 um boundary and the pin coordinates match the
// placeholder exactly (see macro/pin_template.def).
//
// This is a thin wrapper around CF_owire_id_mux (rtl/CF_owire_id_mux.v, merged
// in PR #1). The mux does the reset-held pad mux; the core it instantiates is
// renamed to CF_owire_id_core by macro/build_macro_rtl.sh so it does not
// collide with this module name at GDS merge.
//
// Behaviour (from CF_owire_id_mux):
//   chip_reset_n = 0 (reset held): the 1-Wire ID slave owns the GPIO 0 pad.
//     gpio_out_pin = owire_oeb, output enabled, input enabled, dm = 010.
//   chip_reset_n = 1 (out of reset): every pad control passes through from
//     the user side; the slave is held in reset and off the pin.

`default_nettype none

module CF_owire_id (
`ifdef USE_POWER_PINS
    inout  VPWR,
    inout  VGND,
`endif
    input         chip_reset_n,
    input  [31:0] mask_rev,
    input         gpio_in_pin,
    input         gpio_out_user,         output gpio_out_pin,
    input         gpio_oeb_user,         output gpio_oeb_pin,
    input         gpio_inp_dis_user,     output gpio_inp_dis_pin,
    input         gpio_ib_mode_sel_user, output gpio_ib_mode_sel_pin,
    input         gpio_vtrip_sel_user,   output gpio_vtrip_sel_pin,
    input         gpio_slow_sel_user,    output gpio_slow_sel_pin,
    input         gpio_holdover_user,    output gpio_holdover_pin,
    input         gpio_analog_en_user,   output gpio_analog_en_pin,
    input         gpio_analog_sel_user,  output gpio_analog_sel_pin,
    input         gpio_analog_pol_user,  output gpio_analog_pol_pin,
    input         gpio_dm0_user,         output gpio_dm0_pin,
    input         gpio_dm1_user,         output gpio_dm1_pin,
    input         gpio_dm2_user,         output gpio_dm2_pin
);

    CF_owire_id_mux u_mux (
        .chip_reset_n        (chip_reset_n),
        .mask_rev            (mask_rev),
        .gpio_in_pin         (gpio_in_pin),
        .gpio_out_user       (gpio_out_user),
        .gpio_oeb_user       (gpio_oeb_user),
        .gpio_inp_dis_user   (gpio_inp_dis_user),
        .gpio_dm2_user       (gpio_dm2_user),
        .gpio_dm1_user       (gpio_dm1_user),
        .gpio_dm0_user       (gpio_dm0_user),
        .gpio_analog_en_user (gpio_analog_en_user),
        .gpio_analog_sel_user(gpio_analog_sel_user),
        .gpio_analog_pol_user(gpio_analog_pol_user),
        .gpio_ib_mode_sel_user(gpio_ib_mode_sel_user),
        .gpio_vtrip_sel_user (gpio_vtrip_sel_user),
        .gpio_slow_sel_user  (gpio_slow_sel_user),
        .gpio_holdover_user  (gpio_holdover_user),
        .gpio_out_pin        (gpio_out_pin),
        .gpio_oeb_pin        (gpio_oeb_pin),
        .gpio_inp_dis_pin    (gpio_inp_dis_pin),
        .gpio_dm2_pin        (gpio_dm2_pin),
        .gpio_dm1_pin        (gpio_dm1_pin),
        .gpio_dm0_pin        (gpio_dm0_pin),
        .gpio_analog_en_pin  (gpio_analog_en_pin),
        .gpio_analog_sel_pin (gpio_analog_sel_pin),
        .gpio_analog_pol_pin (gpio_analog_pol_pin),
        .gpio_ib_mode_sel_pin(gpio_ib_mode_sel_pin),
        .gpio_vtrip_sel_pin  (gpio_vtrip_sel_pin),
        .gpio_slow_sel_pin   (gpio_slow_sel_pin),
        .gpio_holdover_pin   (gpio_holdover_pin),
        .ip_busy             ()
    );

endmodule

`default_nettype wire
