// SPDX-FileCopyrightText: 2026 ChipFoundry, a DBA of Umbralogic Technologies LLC
// SPDX-License-Identifier: Apache-2.0

//=============================================================================
// CF_owire_id_mux: user pad controls pass through while chip_reset_n is
// high, and a 1-Wire master can read the ROM while chip_reset_n is held low.
//=============================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_CF_owire_id_mux;

    localparam integer OSC_CYCLES_PER_US = 100;
    localparam integer T_RESET_MIN_US    = 5;
    localparam integer T_PRES_DELAY_US   = 1;
    localparam integer T_PRES_LOW_US     = 3;
    localparam integer T_SAMPLE_US       = 1;
    localparam integer T_READ_LOW_US     = 2;
    localparam [7:0]   FAMILY_CODE = 8'hCF;
    localparam [15:0]  SERIAL_HIGH = 16'hCF1D;
    localparam [31:0]  MASK_REV    = 32'hCAFEBABE;

    localparam integer T_RESET_NS      = 8_000;
    localparam integer T_SLOT_NS       = 4_000;
    localparam integer T_WRITE0_LOW_NS = 3_000;
    localparam integer T_WRITE1_LOW_NS = 500;
    localparam integer T_READ_TRIG_NS  = 500;
    localparam integer T_READ_SAMP_NS  = 1_000;
    localparam integer T_GAP_NS        = 500;

    reg         chip_reset_n;
    reg         master_drive_low;
    reg         gpio_out_user, gpio_oeb_user, gpio_inp_dis_user;
    reg         gpio_dm2_user, gpio_dm1_user, gpio_dm0_user;
    reg         gpio_analog_en_user, gpio_analog_sel_user, gpio_analog_pol_user;
    reg         gpio_ib_mode_sel_user, gpio_vtrip_sel_user;
    reg         gpio_slow_sel_user, gpio_holdover_user;

    wire        gpio_out_pin, gpio_oeb_pin, gpio_inp_dis_pin;
    wire        gpio_dm2_pin, gpio_dm1_pin, gpio_dm0_pin;
    wire        gpio_analog_en_pin, gpio_analog_sel_pin, gpio_analog_pol_pin;
    wire        gpio_ib_mode_sel_pin, gpio_vtrip_sel_pin;
    wire        gpio_slow_sel_pin, gpio_holdover_pin;
    wire        ip_busy;

    // dm=010 releases when gpio_out_pin is 1. The master can also pull low.
    wire        owire_wire = ~master_drive_low & gpio_out_pin;

    integer fail_count;
    integer pass_count;
    reg [7:0] rom_bytes [0:7];

    CF_owire_id_mux #(
        .FAMILY_CODE       (FAMILY_CODE),
        .SERIAL_HIGH       (SERIAL_HIGH),
        .OSC_CYCLES_PER_US (OSC_CYCLES_PER_US),
        .T_RESET_MIN_US    (T_RESET_MIN_US),
        .T_PRES_DELAY_US   (T_PRES_DELAY_US),
        .T_PRES_LOW_US     (T_PRES_LOW_US),
        .T_SAMPLE_US       (T_SAMPLE_US),
        .T_READ_LOW_US     (T_READ_LOW_US)
    ) dut (
        .chip_reset_n          (chip_reset_n),
        .mask_rev              (MASK_REV),
        .gpio_out_user         (gpio_out_user),
        .gpio_oeb_user         (gpio_oeb_user),
        .gpio_inp_dis_user     (gpio_inp_dis_user),
        .gpio_dm2_user         (gpio_dm2_user),
        .gpio_dm1_user         (gpio_dm1_user),
        .gpio_dm0_user         (gpio_dm0_user),
        .gpio_analog_en_user   (gpio_analog_en_user),
        .gpio_analog_sel_user  (gpio_analog_sel_user),
        .gpio_analog_pol_user  (gpio_analog_pol_user),
        .gpio_ib_mode_sel_user (gpio_ib_mode_sel_user),
        .gpio_vtrip_sel_user   (gpio_vtrip_sel_user),
        .gpio_slow_sel_user    (gpio_slow_sel_user),
        .gpio_holdover_user    (gpio_holdover_user),
        .gpio_in_pin           (owire_wire),
        .gpio_out_pin          (gpio_out_pin),
        .gpio_oeb_pin          (gpio_oeb_pin),
        .gpio_inp_dis_pin      (gpio_inp_dis_pin),
        .gpio_dm2_pin          (gpio_dm2_pin),
        .gpio_dm1_pin          (gpio_dm1_pin),
        .gpio_dm0_pin          (gpio_dm0_pin),
        .gpio_analog_en_pin    (gpio_analog_en_pin),
        .gpio_analog_sel_pin   (gpio_analog_sel_pin),
        .gpio_analog_pol_pin   (gpio_analog_pol_pin),
        .gpio_ib_mode_sel_pin  (gpio_ib_mode_sel_pin),
        .gpio_vtrip_sel_pin    (gpio_vtrip_sel_pin),
        .gpio_slow_sel_pin     (gpio_slow_sel_pin),
        .gpio_holdover_pin     (gpio_holdover_pin),
        .ip_busy               (ip_busy)
    );

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

    task check;
        input integer cond;
        input [80*8-1:0] msg;
        begin
            if (!cond) begin
                $display("FAIL: %0s", msg);
                fail_count = fail_count + 1;
            end else begin
                pass_count = pass_count + 1;
            end
        end
    endtask

    task set_user_pattern;
        begin
            gpio_out_user         = 1'b1;
            gpio_oeb_user         = 1'b1;
            gpio_inp_dis_user     = 1'b1;
            gpio_dm2_user         = 1'b1;
            gpio_dm1_user         = 1'b1;
            gpio_dm0_user         = 1'b1;
            gpio_analog_en_user   = 1'b1;
            gpio_analog_sel_user  = 1'b1;
            gpio_analog_pol_user  = 1'b1;
            gpio_ib_mode_sel_user = 1'b1;
            gpio_vtrip_sel_user   = 1'b1;
            gpio_slow_sel_user    = 1'b1;
            gpio_holdover_user    = 1'b1;
        end
    endtask

    task check_user_passthrough;
        begin
            check(gpio_out_pin === gpio_out_user, "gpio_out pass-through");
            check(gpio_oeb_pin === gpio_oeb_user, "gpio_oeb pass-through");
            check(gpio_inp_dis_pin === gpio_inp_dis_user, "gpio_inp_dis pass-through");
            check(gpio_dm2_pin === 1'b1 && gpio_dm1_pin === 1'b1 && gpio_dm0_pin === 1'b1,
                  "gpio_dm pass-through");
            check(gpio_analog_en_pin === 1'b1, "analog_en pass-through");
            check(gpio_analog_sel_pin === 1'b1, "analog_sel pass-through");
            check(gpio_analog_pol_pin === 1'b1, "analog_pol pass-through");
            check(gpio_ib_mode_sel_pin === 1'b1, "ib_mode_sel pass-through");
            check(gpio_vtrip_sel_pin === 1'b1, "vtrip_sel pass-through");
            check(gpio_slow_sel_pin === 1'b1, "slow_sel pass-through");
            check(gpio_holdover_pin === 1'b1, "holdover pass-through");
            check(ip_busy === 1'b0, "slave held in reset while the user owns the pin");
        end
    endtask

    task check_id_pad_config;
        begin
            check(gpio_oeb_pin === 1'b0, "ID mode oeb");
            check(gpio_inp_dis_pin === 1'b0, "ID mode inp_dis");
            check(gpio_dm2_pin === 1'b0 && gpio_dm1_pin === 1'b1 && gpio_dm0_pin === 1'b0,
                  "ID mode dm=010");
            check(gpio_analog_en_pin === 1'b0 && gpio_analog_sel_pin === 1'b0
                  && gpio_analog_pol_pin === 1'b0, "ID mode analog ties");
            check(gpio_ib_mode_sel_pin === 1'b0 && gpio_vtrip_sel_pin === 1'b0
                  && gpio_slow_sel_pin === 1'b0 && gpio_holdover_pin === 1'b0,
                  "ID mode remaining ties");
        end
    endtask

    task master_release; master_drive_low = 1'b0; endtask
    task master_drive;   master_drive_low = 1'b1; endtask

    task master_reset_pulse;
        begin
            master_drive;
            #T_RESET_NS;
            master_release;
        end
    endtask

    task master_wait_presence;
        integer elapsed;
        reg saw_low;
        begin
            saw_low = 1'b0;
            elapsed = 0;
            while (elapsed < 10_000) begin
                if (owire_wire === 1'b0) saw_low = 1'b1;
                #250;
                elapsed = elapsed + 250;
            end
            check(saw_low === 1'b1, "presence pulse while reset is held");
        end
    endtask

    task master_write_bit(input integer bit_val);
        begin
            master_drive;
            if (bit_val) begin
                #T_WRITE1_LOW_NS;
                master_release;
                #(T_SLOT_NS - T_WRITE1_LOW_NS);
            end else begin
                #T_WRITE0_LOW_NS;
                master_release;
                #(T_SLOT_NS - T_WRITE0_LOW_NS);
            end
            #T_GAP_NS;
        end
    endtask

    task master_write_byte(input [7:0] byte_val);
        integer i;
        begin
            for (i = 0; i < 8; i = i + 1)
                master_write_bit((byte_val >> i) & 1);
        end
    endtask

    task master_read_bit(output integer bit_val);
        begin
            master_drive;
            #T_READ_TRIG_NS;
            master_release;
            #(T_READ_SAMP_NS - T_READ_TRIG_NS);
            bit_val = (owire_wire === 1'b0) ? 0 : 1;
            #(T_SLOT_NS - T_READ_SAMP_NS);
            #T_GAP_NS;
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

    initial begin
        integer i;
        reg [63:0] rom;
        reg [55:0] rom_low;
        reg [63:0] expected_rom;

        fail_count = 0;
        pass_count = 0;
        // Start in ID mode so the slave reset has an edge when the user
        // takes the pin back. The async reset only fires on that edge.
        chip_reset_n = 1'b0;
        master_drive_low = 1'b0;
        set_user_pattern;
        #1_000;
        chip_reset_n = 1'b1;
        #1_000;

        // User owns the pin. A long low must not change the pad controls,
        // which is what would happen if the slave were listening.
        check_user_passthrough;
        master_drive;
        #(T_RESET_NS * 2);
        check_user_passthrough;
        master_release;
        #1_000;

        // Hold chip reset. User controls are still the distinctive pattern;
        // the mux must ignore them and force the ID pad config.
        chip_reset_n = 1'b0;
        #2_000;
        check_id_pad_config;
        check(gpio_out_pin === 1'b1, "slave releases the wire while idle");

        master_reset_pulse;
        master_wait_presence;
        #2_000;
        master_write_byte(8'h33);
        #2_000;
        for (i = 0; i < 8; i = i + 1)
            master_read_byte(rom_bytes[i]);
        rom = {rom_bytes[7], rom_bytes[6], rom_bytes[5], rom_bytes[4],
               rom_bytes[3], rom_bytes[2], rom_bytes[1], rom_bytes[0]};
        rom_low = {SERIAL_HIGH, MASK_REV, FAMILY_CODE};
        expected_rom = {crc8_dallas(rom_low), rom_low};
        check(rom === expected_rom, "ROM read while reset is held");
        $display("  ROM 0x%016x expected 0x%016x", rom, expected_rom);

        // Releasing reset gives the pin back and silences the slave.
        chip_reset_n = 1'b1;
        #1_000;
        check_user_passthrough;

        $display("");
        $display("=========================================");
        $display("  CF_owire_id_mux summary");
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
        #5_000_000;
        $display("FAIL: mux testbench timeout");
        $finish(1);
    end

endmodule

`default_nettype wire
