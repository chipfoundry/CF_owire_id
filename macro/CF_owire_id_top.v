// SPDX-FileCopyrightText: 2026 ChipFoundry, a DBA of Umbralogic Technologies LLC
// SPDX-License-Identifier: Apache-2.0
//
// CF_owire_id hardened macro: 1-Wire ID slave + reset-gated pad mux.
//
// Drop-in replacement for the CF_owire_id placeholder cell at tapeout. The
// port list, the 155 x 240 um boundary and the pin coordinates match the
// placeholder exactly (see ip/CF_owire_id/build_abstract.py in the harness).
//
// Behaviour:
//   chip_reset_n = 0  (chip reset held): the 1-Wire ID slave owns the GPIO 0
//                     pad controls. gpio_out_pin = owire_oeb (open-drain
//                     0 = pull the pad low), output enabled, input enabled,
//                     dm = 010. The slave reads gpio_in_pin.
//   chip_reset_n = 1  (out of reset): every control passes straight through
//                     from the user side. The slave is held in reset by the
//                     core and is off the pin.
//
// Mux select is the raw chip_reset_n (not the synchronised core reset), so
// the pad hands over to the user as soon as reset is released.
//
// The core (CF_owire_id_core) is generated from rtl/CF_owire_id.v by
// macro/build_macro_rtl.sh and renamed so it does not collide with this
// module name.

`default_nettype none

module CF_owire_id (
`ifdef USE_POWER_PINS
    inout  VPWR,
    inout  VGND,
`endif
    input         chip_reset_n,
    input  [31:0] mask_rev,
    input         gpio_in_pin,
    input         gpio_out_user,      output gpio_out_pin,
    input         gpio_oeb_user,      output gpio_oeb_pin,
    input         gpio_inp_dis_user,  output gpio_inp_dis_pin,
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

    // ---------------------------------------------------------------------
    // 1-Wire ID core. Active while chip reset is held: rst_n = ~chip_reset_n
    // (core reset is asserted when the chip is out of reset).
    // ---------------------------------------------------------------------
    wire ip_oeb;

    CF_owire_id_core u_core (
        .rst_n     (~chip_reset_n),
        .id_in     (mask_rev),
        .owire_in  (gpio_in_pin),
        .owire_oeb (ip_oeb),
        .busy      ()
    );

    // ---------------------------------------------------------------------
    // Pad control mux. While chip_reset_n is low the ID values are forced
    // onto the pad (open-drain, input enabled); otherwise the user value
    // passes through.
    // ---------------------------------------------------------------------
    assign gpio_out_pin        = chip_reset_n ? gpio_out_user        : ip_oeb;
    assign gpio_oeb_pin        = chip_reset_n ? gpio_oeb_user        : 1'b0;
    assign gpio_inp_dis_pin    = chip_reset_n ? gpio_inp_dis_user    : 1'b0;
    assign gpio_ib_mode_sel_pin = chip_reset_n ? gpio_ib_mode_sel_user : 1'b0;
    assign gpio_vtrip_sel_pin  = chip_reset_n ? gpio_vtrip_sel_user  : 1'b0;
    assign gpio_slow_sel_pin   = chip_reset_n ? gpio_slow_sel_user   : 1'b0;
    assign gpio_holdover_pin   = chip_reset_n ? gpio_holdover_user   : 1'b0;
    assign gpio_analog_en_pin  = chip_reset_n ? gpio_analog_en_user  : 1'b0;
    assign gpio_analog_sel_pin = chip_reset_n ? gpio_analog_sel_user : 1'b0;
    assign gpio_analog_pol_pin = chip_reset_n ? gpio_analog_pol_user : 1'b0;
    assign gpio_dm0_pin        = chip_reset_n ? gpio_dm0_user        : 1'b0;
    assign gpio_dm1_pin        = chip_reset_n ? gpio_dm1_user        : 1'b1;
    assign gpio_dm2_pin        = chip_reset_n ? gpio_dm2_user        : 1'b0;

endmodule

`default_nettype wire
