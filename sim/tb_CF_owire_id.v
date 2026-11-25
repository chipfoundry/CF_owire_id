// SPDX-FileCopyrightText: 2026 ChipFoundry, a DBA of Umbralogic Technologies LLC
// SPDX-License-Identifier: Apache-2.0

//=============================================================================
// Block-level testbench for the CF_owire_id Dallas 1-Wire slave core.
//
// Runs under plain iverilog/vvp -- no Caravel or OpenFrame infrastructure
// is needed.  Used for fast CI smoke checks of the core; the full
// OpenFrame-level test is the cocotb owire_id_test in
// openframe_user_project/verilog/dv/cocotb/.
//
//     iverilog -g2012 -DIVERILOG_SIM -o tb_CF_owire_id.vvp \
//         ../rtl/CF_owire_id.v tb_CF_owire_id.v
//     vvp tb_CF_owire_id.vvp
//
// The testbench:
//   1. Pulls up `owire_wire` with a weak high (modeling the external
//      pull-up on a real 1-Wire bus).  The slave's open-drain output
//      and the master's open-drain output both wired-AND onto it.
//   2. Acts as a 1-Wire master: sends a reset pulse, waits for the
//      slave's presence pulse, sends Read-ROM (0x33), then clocks 64
//      read slots.
//   3. Verifies the 64-bit ROM against {CRC, SERIAL_HIGH, id_in,
//      FAMILY_CODE} with the Dallas 0x8C CRC-8.
//   4. Pulses rst_n again with a different id_in to prove the IP
//      re-arms across resets, and reads that frame too.
//
// 1-Wire slot timings in the DUT are scaled down by ~60x from canonical
// 480/15/120/30/30 us to 5/1/3/1/2 us so the testbench finishes in
// ~hundreds of us of simulated time.  Real silicon should set the IP
// parameters back to the canonical values; the protocol is identical.
//=============================================================================

`default_nettype none
`timescale 1ns / 1ps

module tb_CF_owire_id;

    // ----- DUT parameters (scaled for fast sim, matching openframe demo) -----
    localparam integer OSC_CYCLES_PER_US = 100;
    localparam integer T_RESET_MIN_US    = 5;
    localparam integer T_PRES_DELAY_US   = 1;
    localparam integer T_PRES_LOW_US     = 3;
    localparam integer T_SAMPLE_US       = 1;
    localparam integer T_READ_LOW_US     = 2;

    localparam [7:0]   FAMILY_CODE = 8'hCF;
    localparam [15:0]  SERIAL_HIGH = 16'hCF1D;

    // ----- Master timing (ns) -- matches the OpenFrame cocotb test --------
    localparam integer T_RESET_NS      = 8_000;
    localparam integer T_SLOT_NS       = 4_000;
    localparam integer T_WRITE0_LOW_NS = 3_000;
    localparam integer T_WRITE1_LOW_NS = 500;
    localparam integer T_READ_TRIG_NS  = 500;
    localparam integer T_READ_SAMP_NS  = 1_000;
    localparam integer T_GAP_NS        = 500;

    // ----- DUT signals --------------------------------------------------
    reg         rst_n;
    reg  [31:0] id_in;

    // Open-drain wire model.
    //
    // A real 1-Wire bus has a single net, weak-pulled high, that any
    // participant can pull strong-low.  We model that here as an explicit
    // AND of the inverted "drive low" signals from each side; whichever
    // side asserts low forces the wire low, otherwise the wire is high.
    reg         master_drive_low;
    wire        slave_oeb;            // slave's open-drain enable bar
    wire        owire_wire = ~master_drive_low & slave_oeb;

    wire        slave_busy;

    CF_owire_id #(
        .FAMILY_CODE       (FAMILY_CODE),
        .SERIAL_HIGH       (SERIAL_HIGH),
        .OSC_CYCLES_PER_US (OSC_CYCLES_PER_US),
        .T_RESET_MIN_US    (T_RESET_MIN_US),
        .T_PRES_DELAY_US   (T_PRES_DELAY_US),
        .T_PRES_LOW_US     (T_PRES_LOW_US),
        .T_SAMPLE_US       (T_SAMPLE_US),
        .T_READ_LOW_US     (T_READ_LOW_US)
    ) dut (
        .rst_n     (rst_n),
        .id_in     (id_in),
        .owire_in  (owire_wire),
        .owire_oeb (slave_oeb),
        .busy      (slave_busy)
    );

    // ----- Test bookkeeping ---------------------------------------------
    reg [7:0] rom_bytes [0:7];
    integer   pass_count = 0;
    integer   fail_count = 0;

    // CRC-8 (Dallas/Maxim 0x8C, LSB-first feedback).
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

    //-------------------------------------------------------------------------
    // 1-Wire master tasks.  All timing in ns.
    //-------------------------------------------------------------------------
    task master_release;
        master_drive_low = 1'b0;
    endtask

    task master_drive;
        master_drive_low = 1'b1;
    endtask

    task master_reset_pulse;
        begin
            master_drive;
            #T_RESET_NS;
            master_release;
        end
    endtask

    // Poll for the presence pulse for a generous window after the reset
    // pulse: must see the wire go low at some point.
    task master_wait_presence;
        integer elapsed;
        reg saw_low;
        begin
            saw_low = 1'b0;
            elapsed = 0;
            while (elapsed < 10_000) begin
                if (owire_wire === 1'b0)
                    saw_low = 1'b1;
                #250;
                elapsed = elapsed + 250;
            end
            if (!saw_low) begin
                $display("FAIL: no presence pulse from slave");
                fail_count = fail_count + 1;
                $finish(1);
            end
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

    //-------------------------------------------------------------------------
    // One full read-and-check pass: reset, presence, Read-ROM, 64 read slots,
    // then assemble + verify the ROM against the expected value built from
    // the current id_in.
    //-------------------------------------------------------------------------
    task run_read_rom_and_check(input [31:0] expected_id, input [8*48-1:0] label);
        integer i;
        reg [63:0] rom;
        reg [55:0] rom_low;
        reg [7:0]  expected_crc;
        reg [63:0] expected_rom;
        reg [7:0]  got_family;
        reg [47:0] got_serial;
        reg [7:0]  got_crc;
        begin
            // Idle the bus, then issue reset + presence.
            master_release;
            #2_000;
            master_reset_pulse;
            master_wait_presence;
            #2_000;

            // Read-ROM command (0x33).
            master_write_byte(8'h33);
            #2_000;

            // 64 read slots, LSB-first per byte.
            for (i = 0; i < 8; i = i + 1)
                master_read_byte(rom_bytes[i]);

            rom = {rom_bytes[7], rom_bytes[6], rom_bytes[5], rom_bytes[4],
                   rom_bytes[3], rom_bytes[2], rom_bytes[1], rom_bytes[0]};

            got_family = rom[7:0];
            got_serial = rom[55:8];
            got_crc    = rom[63:56];

            rom_low      = {SERIAL_HIGH, expected_id, FAMILY_CODE};
            expected_crc = crc8_dallas(rom_low);
            expected_rom = {expected_crc, rom_low};

            $display("");
            $display("---- %0s ----", label);
            $display("  raw ROM bytes (LSB-first) : %02x %02x %02x %02x %02x %02x %02x %02x",
                     rom_bytes[0], rom_bytes[1], rom_bytes[2], rom_bytes[3],
                     rom_bytes[4], rom_bytes[5], rom_bytes[6], rom_bytes[7]);
            $display("  64-bit ROM                : 0x%016x", rom);
            $display("  family code               : 0x%02x  (expected 0x%02x)", got_family, FAMILY_CODE);
            $display("  serial[31:0] = mask_rev   : 0x%08x  (expected 0x%08x)", got_serial[31:0], expected_id);
            $display("  serial[47:32] = magic     : 0x%04x  (expected 0x%04x)", got_serial[47:32], SERIAL_HIGH);
            $display("  CRC-8 (Dallas 0x8C)       : 0x%02x  (recomputed 0x%02x)", got_crc, expected_crc);

            if (rom !== expected_rom) begin
                $display("  FAIL: ROM mismatch (got 0x%016x, expected 0x%016x)",
                         rom, expected_rom);
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS");
                pass_count = pass_count + 1;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Stuck-state recovery.  Power-up with random flops can park the FSM in
    // a state that holds owire_oeb low (S_TX_HOLD and S_PRES_LOW can do so
    // with nothing to release them).  Force that condition and check that the
    // sustained-low watchdog releases the line (within ~T_RESET_MIN_US) and
    // the slave returns to S_CMD_WAIT.  Without the watchdog the line stays
    // low forever and this check fails.
    //-------------------------------------------------------------------------
    task recover_from_stuck_state(input [3:0] forced_state, input [8*48-1:0] label);
        integer elapsed;
        reg     saw_release;
        begin
            master_release;
            #2_000;

            // Reproduce the deadlock: the master pulls the line low briefly
            // while the FSM is parked in a state that waits for the wire to
            // rise and the slave is driving low.  Then the master releases,
            // but the slave keeps the line low and nothing can bring it high.
            master_drive;
            #500;
            dut.state     = forced_state;
            dut.owire_oeb = 1'b0;
            #200;
            master_release;
            #500;

            if (owire_wire !== 1'b0) begin
                $display("FAIL [%0s]: forced stuck state did not hold the wire low", label);
                fail_count = fail_count + 1;
            end

            // Watch for the wire going high again within 4 * T_RESET_MIN_US.
            saw_release = 1'b0;
            elapsed     = 0;
            while (elapsed < 4 * T_RESET_MIN_US * 1000) begin
                #100;
                elapsed = elapsed + 100;
                if (owire_wire === 1'b1) saw_release = 1'b1;
            end

            $display("");
            $display("---- stuck-state recovery: %0s ----", label);
            $display("  line released by watchdog : %0s", saw_release ? "yes" : "no");
            $display("  slave state after recover : %0d (expect 4 = S_CMD_WAIT)", dut.state);
            if (!saw_release || dut.state != 4'd4) begin
                $display("  FAIL: slave still stuck");
                fail_count = fail_count + 1;
            end else begin
                $display("  PASS");
                pass_count = pass_count + 1;
            end
        end
    endtask

    //-------------------------------------------------------------------------
    // Drive the test.
    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_CF_owire_id.vcd");
        $dumpvars(0, tb_CF_owire_id);

        rst_n            = 1'b0;
        master_drive_low = 1'b0;
        id_in            = 32'hCAFEBABE;
        #1_000;
        rst_n = 1'b1;
        #2_000;

        run_read_rom_and_check(32'hCAFEBABE, "frame 1: ID = 0xCAFEBABE");

        // Pulse reset, switch the id, prove re-trigger across resets.
        #5_000;
        rst_n = 1'b0;
        id_in = 32'h12345678;
        #2_000;
        rst_n = 1'b1;
        #2_000;

        run_read_rom_and_check(32'h12345678, "frame 2: ID = 0x12345678");

        // Stuck-state recovery (see recover_from_stuck_state).
        recover_from_stuck_state(4'd9, "forced S_TX_HOLD with owire_oeb low");
        recover_from_stuck_state(4'd6, "forced S_CMD_HOLD with owire_oeb low");
        run_read_rom_and_check(32'h12345678, "frame 3: ID after stuck-state recovery");

        $display("");
        $display("=========================================");
        $display("  CF_owire_id testbench summary");
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

    // Hard timeout: ~5 ms of sim time is plenty for two full reads.
    initial begin
        #5_000_000;
        $display("FAIL: testbench timeout");
        $finish(1);
    end

endmodule

`default_nettype wire
