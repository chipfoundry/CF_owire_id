// SPDX-FileCopyrightText: 2026 ChipFoundry, a DBA of Umbralogic Technologies LLC
// SPDX-License-Identifier: Apache-2.0
//
// Macro-level testbench for CF_owire_id (top) + CF_owire_id_core.
//
// Drives the 1-Wire bus through the macro's real pins. The GPIO 0 pad is a
// model: it pulls low when gpio_oeb_pin = 0 and gpio_out_pin = 0, otherwise
// releases. The external pull-up is implicit.
//
// Checks:
//   1. chip reset held: a stock 1-Wire master reads the 64-bit ROM.
//   2. chip reset held, after a second ID value: ROM reflects the new mask_rev.
//   3. chip out of reset: the slave is OFF the pin. A master reset pulse must
//      not get a presence pulse, and the mux passes the user controls through.
//   4. pad control values during reset are the ID values (oeb=0, inp_dis=0,
//      dm=010, others 0) and the user values pass through after reset.
//
// Run:
//   iverilog -g2012 -DIVERILOG_SIM -o tb_macro.vvp ../rtl/CF_owire_id.v \
//       CF_owire_id_core.v CF_owire_id_top.v tb_macro.v   (see Makefile)

`default_nettype none
`timescale 1ns / 1ps

module tb_macro;

    localparam [7:0]  FAMILY_CODE = 8'hCF;
    localparam [15:0] SERIAL_HIGH = 16'hCF1D;

    // Master timing (ns). Core slot timings are scaled in defparam below.
    localparam integer T_RESET_NS      = 8_000;
    localparam integer T_SLOT_NS       = 4_000;
    localparam integer T_WRITE0_LOW_NS = 3_000;
    localparam integer T_WRITE1_LOW_NS = 500;
    localparam integer T_READ_TRIG_NS  = 500;
    localparam integer T_READ_SAMP_NS  = 1_000;
    localparam integer T_GAP_NS        = 500;

    reg         chip_reset_n;
    reg  [31:0] mask_rev;
    reg         master_drive_low;

    // user-side pad controls (what the design would drive when out of reset)
    reg         gpio_out_user, gpio_oeb_user, gpio_inp_dis_user;
    reg         gpio_ib_mode_sel_user, gpio_vtrip_sel_user, gpio_slow_sel_user;
    reg         gpio_holdover_user, gpio_analog_en_user, gpio_analog_sel_user;
    reg         gpio_analog_pol_user, gpio_dm0_user, gpio_dm1_user, gpio_dm2_user;

    // macro outputs
    wire gpio_out_pin, gpio_oeb_pin, gpio_inp_dis_pin, gpio_ib_mode_sel_pin;
    wire gpio_vtrip_sel_pin, gpio_slow_sel_pin, gpio_holdover_pin;
    wire gpio_analog_en_pin, gpio_analog_sel_pin, gpio_analog_pol_pin;
    wire gpio_dm0_pin, gpio_dm1_pin, gpio_dm2_pin;

    // Pad model: open-drain pull-low when enabled and driven low.
    wire pad_pull_low = (gpio_oeb_pin == 1'b0) && (gpio_out_pin == 1'b0);
    wire owire_wire   = ~master_drive_low & ~pad_pull_low;   // pulled high externally
    wire gpio_in_pin  = owire_wire;

    CF_owire_id dut (
        .chip_reset_n        (chip_reset_n),
        .mask_rev            (mask_rev),
        .gpio_in_pin         (gpio_in_pin),
        .gpio_out_user       (gpio_out_user),       .gpio_out_pin        (gpio_out_pin),
        .gpio_oeb_user       (gpio_oeb_user),       .gpio_oeb_pin        (gpio_oeb_pin),
        .gpio_inp_dis_user   (gpio_inp_dis_user),   .gpio_inp_dis_pin    (gpio_inp_dis_pin),
        .gpio_ib_mode_sel_user(gpio_ib_mode_sel_user), .gpio_ib_mode_sel_pin(gpio_ib_mode_sel_pin),
        .gpio_vtrip_sel_user (gpio_vtrip_sel_user), .gpio_vtrip_sel_pin  (gpio_vtrip_sel_pin),
        .gpio_slow_sel_user  (gpio_slow_sel_user),  .gpio_slow_sel_pin   (gpio_slow_sel_pin),
        .gpio_holdover_user  (gpio_holdover_user),  .gpio_holdover_pin   (gpio_holdover_pin),
        .gpio_analog_en_user (gpio_analog_en_user), .gpio_analog_en_pin  (gpio_analog_en_pin),
        .gpio_analog_sel_user(gpio_analog_sel_user), .gpio_analog_sel_pin(gpio_analog_sel_pin),
        .gpio_analog_pol_user(gpio_analog_pol_user), .gpio_analog_pol_pin(gpio_analog_pol_pin),
        .gpio_dm0_user       (gpio_dm0_user),       .gpio_dm0_pin        (gpio_dm0_pin),
        .gpio_dm1_user       (gpio_dm1_user),       .gpio_dm1_pin        (gpio_dm1_pin),
        .gpio_dm2_user       (gpio_dm2_user),       .gpio_dm2_pin        (gpio_dm2_pin)
    );

    // Scale the core's slot timings for simulation (as in the core testbench).
    defparam dut.u_core.T_RESET_MIN_US = 5;
    defparam dut.u_core.T_PRES_DELAY_US = 1;
    defparam dut.u_core.T_PRES_LOW_US  = 3;
    defparam dut.u_core.T_SAMPLE_US    = 1;
    defparam dut.u_core.T_READ_LOW_US  = 2;

    integer pass_count = 0;
    integer fail_count = 0;
    reg [7:0] rom_bytes [0:7];

    function [7:0] crc8_dallas;
        input [55:0] data;
        integer i;
        reg [7:0] c;
        reg fb;
        begin
            c = 8'h00;
            for (i = 0; i < 56; i = i + 1) begin
                fb = c[0] ^ data[i];
                c  = {1'b0, c[7:1]};
                if (fb) c = c ^ 8'h8C;
            end
            crc8_dallas = c;
        end
    endfunction

    task master_release; master_drive_low = 1'b0; endtask
    task master_drive;   master_drive_low = 1'b1; endtask

    task master_reset_pulse;
        begin
            master_drive;
            #T_RESET_NS;
            master_release;
        end
    endtask

    // Returns 1 if a presence pulse (wire low, not caused by the master) is seen.
    task master_wait_presence(output saw_low);
        integer elapsed;
        begin
            saw_low = 1'b0;
            elapsed = 0;
            // Let the master release settle: the wire is still low in the
            // same timestep as the release. A real presence pulse starts ~1 us
            // after the reset pulse ends, so this delay cannot hide one.
            #100;
            while (elapsed < 10_000) begin
                if (owire_wire === 1'b0) saw_low = 1'b1;
                #250;
                elapsed = elapsed + 250;
            end
        end
    endtask

    task master_write_bit(input integer bit_val);
        begin
            master_drive;
            if (bit_val) begin
                #T_WRITE1_LOW_NS; master_release; #(T_SLOT_NS - T_WRITE1_LOW_NS);
            end else begin
                #T_WRITE0_LOW_NS; master_release; #(T_SLOT_NS - T_WRITE0_LOW_NS);
            end
            #T_GAP_NS;
        end
    endtask

    task master_write_byte(input [7:0] byte_val);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1) master_write_bit((byte_val >> i) & 1);
        end
    endtask

    task master_read_bit(output integer bit_val);
        begin
            master_drive; #T_READ_TRIG_NS; master_release;
            #(T_READ_SAMP_NS - T_READ_TRIG_NS);
            bit_val = (owire_wire === 1'b0) ? 0 : 1;
            #(T_SLOT_NS - T_READ_SAMP_NS); #T_GAP_NS;
        end
    endtask

    task master_read_byte(output [7:0] byte_val);
        integer i, bit_val;
        begin
            byte_val = 8'h00;
            for (i = 0; i < 8; i = i + 1) begin
                master_read_bit(bit_val);
                byte_val[i] = bit_val[0];
            end
        end
    endtask

    // Full Read-ROM transaction; checks the ROM against the current mask_rev.
    task read_rom_and_check(input [8*48-1:0] label);
        integer i;
        reg saw;
        reg [63:0] rom, expected_rom;
        reg [55:0] rom_low;
        begin
            master_release; #2_000;
            master_reset_pulse;
            master_wait_presence(saw);
            if (!saw) begin
                $display("FAIL [%0s]: no presence pulse", label);
                fail_count = fail_count + 1;
            end
            #2_000;
            master_write_byte(8'h33);
            #2_000;
            for (i = 0; i < 8; i = i + 1) master_read_byte(rom_bytes[i]);
            rom = {rom_bytes[7], rom_bytes[6], rom_bytes[5], rom_bytes[4],
                   rom_bytes[3], rom_bytes[2], rom_bytes[1], rom_bytes[0]};
            rom_low      = {SERIAL_HIGH, mask_rev, FAMILY_CODE};
            expected_rom = {crc8_dallas(rom_low), rom_low};
            $display("---- %0s ----", label);
            $display("  ROM = 0x%016x  expected 0x%016x", rom, expected_rom);
            if (rom !== expected_rom) begin
                $display("  FAIL: ROM mismatch");
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS");
                pass_count = pass_count + 1;
            end
        end
    endtask

    initial begin
        // Power-up with chip reset held. The ID core is active (not in reset),
        // so its flops are not cleared by reset. Model the worst case: random
        // flops parked in S_TX_HOLD with owire_oeb low, holding the line low.
        // The sustained-low watchdog must release the line before the ROM read.
        dut.u_core.state       = 4'd9;
        dut.u_core.owire_oeb   = 1'b0;
        dut.u_core.cnt         = 0;
        dut.u_core.cmd_sh      = 0;
        dut.u_core.cmd_bit_idx = 0;
        dut.u_core.tx_bit_idx  = 0;
        dut.u_core.low_cnt     = 0;
        dut.u_core.owire_in_s1 = 1'b1;
        dut.u_core.owire_in_s2 = 1'b1;
        dut.u_core.wire_lvl_d  = 1'b1;
        dut.u_core.rst_s1      = 1'b1;
        dut.u_core.rst_s2      = 1'b1;

        chip_reset_n = 1'b0;   // chip in reset: ID active
        master_drive_low = 1'b0;
        mask_rev = 32'hCAFEBABE;
        gpio_out_user = 1; gpio_oeb_user = 1; gpio_inp_dis_user = 0;
        gpio_ib_mode_sel_user = 0; gpio_vtrip_sel_user = 0; gpio_slow_sel_user = 0;
        gpio_holdover_user = 0; gpio_analog_en_user = 0; gpio_analog_sel_user = 0;
        gpio_analog_pol_user = 0; gpio_dm0_user = 0; gpio_dm1_user = 1; gpio_dm2_user = 0;

        // Reset-time pad values: ID drives the pad. Check the control values.
        #3_000;
        if (gpio_oeb_pin !== 1'b0 || gpio_inp_dis_pin !== 1'b0 ||
            gpio_dm0_pin !== 1'b0 || gpio_dm1_pin !== 1'b1 || gpio_dm2_pin !== 1'b0 ||
            gpio_ib_mode_sel_pin !== 1'b0 || gpio_vtrip_sel_pin !== 1'b0 ||
            gpio_slow_sel_pin !== 1'b0 || gpio_holdover_pin !== 1'b0 ||
            gpio_analog_en_pin !== 1'b0 || gpio_analog_sel_pin !== 1'b0 ||
            gpio_analog_pol_pin !== 1'b0) begin
            $display("FAIL: pad controls not in ID mode during reset");
            fail_count = fail_count + 1;
        end else begin
            $display("  pad controls in ID mode during reset: PASS");
            pass_count = pass_count + 1;
        end

        // Power-up recovery: the watchdog releases the stuck line within
        // ~T_RESET_MIN_US and the slave's presence pulse ends by ~10 us.
        #7_000;
        if (owire_wire !== 1'b1) begin
            $display("FAIL: line still held low after power-up (watchdog)");
            fail_count = fail_count + 1;
        end else begin
            $display("---- power-up stuck line released ----");
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        read_rom_and_check("1: reset held, ID 0xCAFEBABE");

        // Second ID value while still in reset.
        #5_000;
        mask_rev = 32'h12345678;
        #2_000;
        read_rom_and_check("2: reset held, ID 0x12345678");

        // Release reset: the slave must come off the pin.
        chip_reset_n = 1'b1;
        #2_000;
        if (gpio_out_pin !== gpio_out_user || gpio_oeb_pin !== gpio_oeb_user ||
            gpio_inp_dis_pin !== gpio_inp_dis_user || gpio_dm1_pin !== gpio_dm1_user ||
            gpio_dm2_pin !== gpio_dm2_user) begin
            $display("FAIL: pad controls do not pass through after reset");
            fail_count = fail_count + 1;
        end else begin
            $display("---- 3: out of reset, controls pass through ----");
            $display("  PASS");
            pass_count = pass_count + 1;
        end

        // Master reset pulse with the chip out of reset: no presence expected.
        master_release; #2_000;
        master_reset_pulse;
        begin : no_presence
            reg saw;
            master_wait_presence(saw);
            if (saw) begin
                $display("FAIL: slave answered a reset while the chip is out of reset");
                fail_count = fail_count + 1;
            end else begin
                $display("---- 4: out of reset, no presence ----");
                $display("  PASS");
                pass_count = pass_count + 1;
            end
        end

        // Drive a user value on a pad control and check it reaches the pin.
        gpio_out_user = 0; gpio_oeb_user = 0; #1_000;
        if (gpio_out_pin !== 1'b0 || gpio_oeb_pin !== 1'b0) begin
            $display("FAIL: user pad output not passed through");
            fail_count = fail_count + 1;
        end else begin
            $display("---- 5: user output reaches pad ----");
            $display("  PASS");
            pass_count = pass_count + 1;
        end
        gpio_out_user = 1; gpio_oeb_user = 1; #1_000;

        // Second reset cycle: ID is readable again with the current mask_rev.
        chip_reset_n = 1'b0;
        #3_000;
        read_rom_and_check("6: reset re-asserted, ID 0x12345678");

        $display("");
        $display("=========================================");
        $display("  CF_owire_id macro testbench summary");
        $display("    passed : %0d", pass_count);
        $display("    failed : %0d", fail_count);
        $display("=========================================");
        if (fail_count != 0) begin
            $display("RESULT: FAIL");
            $finish(1);
        end else begin
            $display("RESULT: PASS");
            $finish;
        end
    end

    initial begin
        #20_000_000;
        $display("FAIL: testbench timeout");
        $finish(1);
    end

endmodule

`default_nettype wire
