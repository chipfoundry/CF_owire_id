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
// Module: CF_owire_id
//
// Dallas/Maxim 1-Wire slave for ChipFoundry Openframe projects.  Implements
// the minimum slave behavior needed to publish the 32-bit padframe
// `mask_rev` value as a DS2401-compatible 64-bit ROM ID over a single
// open-drain bidirectional pin.  A 1-Wire master on the host PCB drives
// reset / read slots; the chip responds with presence + ROM data without
// needing any external clock connection (the IP embeds its own oscillator).
//
// ROM layout (transmitted LSB-first, per Dallas 1-Wire convention):
//   bits  7:0   family code     (parameter FAMILY_CODE, default 0xCF)
//   bits 39:8   serial[31:0]    = id_in (typically padframe mask_rev)
//   bits 55:40  serial[47:32]   = parameter SERIAL_HIGH (default 0xCF1D)
//   bits 63:56  CRC-8           computed over bits 0..55, Dallas poly 0x8C
//
// Supported command set (after reset + presence):
//   0x33 Read ROM     -> shift the 64-bit ROM out, LSB-first.
//   everything else   -> return to idle without responding further.
//
// Timing assumes the IP's internal oscillator runs at roughly 100 MHz, i.e.
// `OSC_CYCLES_PER_US` cycles per microsecond.  Override OSC_CYCLES_PER_US
// to scale every threshold for a different osc frequency or for shorter
// simulation runtimes.
//
// Pin protocol (open-drain emulation):
//   owire_oeb = 0 -> chip drives the wire low
//   owire_oeb = 1 -> chip releases (high-Z); the board's external pull-up
//                    (or the OpenFrame pad's INPUT_PU mode) brings the line
//                    high.
//=============================================================================

`default_nettype none
`timescale 1ns / 1ps

module CF_owire_id #(
    parameter [7:0]  FAMILY_CODE        = 8'hCF,
    parameter [15:0] SERIAL_HIGH        = 16'hCF1D,
    parameter integer OSC_CYCLES_PER_US = 100,   // osc cycles per 1 us
    // Slot timing in microseconds (Dallas 1-Wire standard speed):
    parameter integer T_RESET_MIN_US    = 480,   // master low for reset must be >= this
    parameter integer T_PRES_DELAY_US   = 15,    // wait after master release before presence
    parameter integer T_PRES_LOW_US     = 120,   // hold presence low for this long
    parameter integer T_SAMPLE_US       = 30,    // sample point for master-write bits
    parameter integer T_READ_LOW_US     = 30     // hold low for slave-write-0 in read slot
)(
    input  wire        rst_n,        // active-low chip reset (e.g. resetb_l)
    input  wire [31:0] id_in,        // bits [39:8] of ROM (e.g. mask_rev)
    input  wire        owire_in,     // 1-Wire pad input (driven by master / pull-up)
    output reg         owire_oeb,    // 1-Wire pad output enable bar (0 = drive low)
    output wire        busy          // 1 while the slave FSM is engaged in any transaction
);

    //-------------------------------------------------------------------------
    // Internal oscillator
    // -- In simulation (COCOTB_SIM or IVERILOG_SIM defined) we use a
    //    behavioral oscillator so the test runs deterministically.
    // -- In PnR/synthesis we'd substitute a sky130 inverter ring; that
    //    instantiation lives behind `ifdef SYNTHESIS` to keep this IP
    //    PDK-agnostic in source form. Drop the ring into your synthesis
    //    wrapper or replace this block with a vendor cell as needed.
    //-------------------------------------------------------------------------
    wire osc_clk;

`ifdef COCOTB_SIM
    reg sim_osc = 1'b0;
    initial sim_osc = 1'b0;
    always #5 sim_osc = ~sim_osc;     // 100 MHz -> 100 cycles/us
    assign osc_clk = sim_osc;
`elsif IVERILOG_SIM
    reg sim_osc = 1'b0;
    initial sim_osc = 1'b0;
    always #5 sim_osc = ~sim_osc;
    assign osc_clk = sim_osc;
`elsif SYNTHESIS
    // Synthesizable ring oscillator placeholder.  Replace these inverter
    // instances with PDK-keep-attribute cells when integrating into a real
    // chip flow.  Example for sky130:
    //   (* keep = "true" *) sky130_fd_sc_hd__inv_2 i0 (.A(n2), .Y(n0));
    //   (* keep = "true" *) sky130_fd_sc_hd__inv_2 i1 (.A(n0), .Y(n1));
    //   (* keep = "true" *) sky130_fd_sc_hd__inv_2 i2 (.A(n1), .Y(n2));
    wire n0, n1, n2;
    assign #1 n0 = ~n2;
    assign #1 n1 = ~n0;
    assign #1 n2 = ~n1;
    assign osc_clk = n2;
`else
    // Default RTL-simulation fallback (same behavioral osc).
    reg sim_osc = 1'b0;
    initial sim_osc = 1'b0;
    always #5 sim_osc = ~sim_osc;
    assign osc_clk = sim_osc;
`endif

    //-------------------------------------------------------------------------
    // Synchronize the 1-Wire input into the osc_clk domain.
    //-------------------------------------------------------------------------
    reg owire_in_s1, owire_in_s2;
    always @(posedge osc_clk or negedge rst_n) begin
        if (!rst_n) begin
            owire_in_s1 <= 1'b1;
            owire_in_s2 <= 1'b1;
        end else begin
            owire_in_s1 <= owire_in;
            owire_in_s2 <= owire_in_s1;
        end
    end
    wire wire_lvl = owire_in_s2;

    //-------------------------------------------------------------------------
    // Edge detector on the synchronized wire.
    //-------------------------------------------------------------------------
    reg wire_lvl_d;
    always @(posedge osc_clk or negedge rst_n) begin
        if (!rst_n) wire_lvl_d <= 1'b1;
        else        wire_lvl_d <= wire_lvl;
    end
    wire wire_fall = (wire_lvl_d == 1'b1) && (wire_lvl == 1'b0);
    wire wire_rise = (wire_lvl_d == 1'b0) && (wire_lvl == 1'b1);

    //-------------------------------------------------------------------------
    // ROM ID assembly + CRC-8 (Dallas/Maxim polynomial x^8 + x^5 + x^4 + 1,
    // reflected representation 0x8C).
    //-------------------------------------------------------------------------
    wire [55:0] rom_low = {SERIAL_HIGH, id_in, FAMILY_CODE};

    function [7:0] crc8_dallas;
        input [55:0] data;
        integer i;
        reg [7:0] c;
        reg bit_in, fb;
        begin
            c = 8'h00;
            for (i = 0; i < 56; i = i + 1) begin
                bit_in = data[i];
                fb = c[0] ^ bit_in;
                c = {1'b0, c[7:1]};
                if (fb) c = c ^ 8'h8C;
            end
            crc8_dallas = c;
        end
    endfunction

    wire [7:0]  crc8    = crc8_dallas(rom_low);
    wire [63:0] rom_id  = {crc8, rom_low};

    //-------------------------------------------------------------------------
    // Timing constants (in osc_clk cycles).  Recomputed from microsecond
    // parameters and OSC_CYCLES_PER_US so simulation can shrink them.
    //-------------------------------------------------------------------------
    localparam integer C_RESET_MIN  = T_RESET_MIN_US  * OSC_CYCLES_PER_US;
    localparam integer C_PRES_DELAY = T_PRES_DELAY_US * OSC_CYCLES_PER_US;
    localparam integer C_PRES_LOW   = T_PRES_LOW_US   * OSC_CYCLES_PER_US;
    localparam integer C_SAMPLE     = T_SAMPLE_US     * OSC_CYCLES_PER_US;
    localparam integer C_READ_LOW   = T_READ_LOW_US   * OSC_CYCLES_PER_US;

    // Width sized to comfortably hold the longest counter (reset min).
    // Pick 24 bits -> up to 16.7M cycles (~167 ms at 100 MHz).  Plenty.
    localparam integer CW = 24;

    //-------------------------------------------------------------------------
    // FSM
    //-------------------------------------------------------------------------
    localparam [3:0] S_IDLE       = 4'd0;  // wire idle high; waiting for low
    localparam [3:0] S_LOW_COUNT  = 4'd1;  // wire is low; counting duration
    localparam [3:0] S_PRES_DELAY = 4'd2;  // master released after reset; wait T_PRES_DELAY
    localparam [3:0] S_PRES_LOW   = 4'd3;  // drive presence low for T_PRES_LOW
    localparam [3:0] S_CMD_WAIT   = 4'd4;  // wait for next master falling edge (cmd bit slot)
    localparam [3:0] S_CMD_SAMP   = 4'd5;  // count T_SAMPLE then sample wire_lvl
    localparam [3:0] S_CMD_HOLD   = 4'd6;  // wait for wire to return high before next bit
    localparam [3:0] S_TX_WAIT    = 4'd7;  // wait for master falling edge (read slot)
    localparam [3:0] S_TX_DRIVE   = 4'd8;  // if bit=0, hold low for T_READ_LOW
    localparam [3:0] S_TX_HOLD    = 4'd9;  // release, wait for wire high before next bit

    reg [3:0]    state;
    reg [CW-1:0] cnt;
    reg [7:0]    cmd_sh;
    reg [3:0]    cmd_bit_idx;
    reg [6:0]    tx_bit_idx;   // 0..63

    // Public busy flag: 1 whenever the slave is doing anything other than
    // sitting at S_IDLE listening for a master reset.  Useful as a hint to
    // user logic that shares the same open-drain wire (see CF_owire_id_shared)
    // -- e.g. to avoid pulling the wire low during a transaction in flight.
    assign busy = (state != S_IDLE);

    // ROM-out shifted out LSB-first.  We just index rom_id[tx_bit_idx].
    wire tx_bit_val = rom_id[tx_bit_idx];

    always @(posedge osc_clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            cnt         <= {CW{1'b0}};
            cmd_sh      <= 8'h00;
            cmd_bit_idx <= 4'd0;
            tx_bit_idx  <= 7'd0;
            owire_oeb   <= 1'b1;     // released (high-Z)
        end else begin
            case (state)
                S_IDLE: begin
                    owire_oeb <= 1'b1;
                    cnt       <= {CW{1'b0}};
                    if (wire_fall) begin
                        state <= S_LOW_COUNT;
                        cnt   <= {CW{1'b0}};
                    end
                end

                // Master is holding the wire low.  Count until it rises.
                S_LOW_COUNT: begin
                    if (wire_lvl == 1'b0) begin
                        cnt <= cnt + 1'b1;
                    end else begin
                        // Wire just rose. Was this a reset pulse?
                        if (cnt >= C_RESET_MIN[CW-1:0]) begin
                            // Yes: schedule presence response.
                            cnt   <= {CW{1'b0}};
                            state <= S_PRES_DELAY;
                        end else begin
                            // Too short to be reset -> ignore and go back to idle.
                            state <= S_IDLE;
                        end
                    end
                end

                S_PRES_DELAY: begin
                    if (cnt < C_PRES_DELAY[CW-1:0]) begin
                        cnt <= cnt + 1'b1;
                    end else begin
                        cnt       <= {CW{1'b0}};
                        owire_oeb <= 1'b0;   // assert presence low
                        state     <= S_PRES_LOW;
                    end
                end

                S_PRES_LOW: begin
                    if (cnt < C_PRES_LOW[CW-1:0]) begin
                        cnt <= cnt + 1'b1;
                    end else begin
                        owire_oeb   <= 1'b1;   // release
                        cnt         <= {CW{1'b0}};
                        cmd_bit_idx <= 4'd0;
                        cmd_sh      <= 8'h00;
                        state       <= S_CMD_WAIT;
                    end
                end

                // Wait for master to drop the wire to start a write slot.
                S_CMD_WAIT: begin
                    if (wire_fall) begin
                        cnt   <= {CW{1'b0}};
                        state <= S_CMD_SAMP;
                    end
                end

                // Count T_SAMPLE_US after master's falling edge, then
                // sample the wire to capture the master-write bit.
                S_CMD_SAMP: begin
                    if (cnt < C_SAMPLE[CW-1:0]) begin
                        cnt <= cnt + 1'b1;
                    end else begin
                        // LSB-first: shift in at the high end so after 8 bits
                        // cmd_sh has the byte left-aligned -> shift right once
                        // we have 8.  But simplest: cmd_sh[cmd_bit_idx] <= sample.
                        cmd_sh[cmd_bit_idx[2:0]] <= wire_lvl;
                        state <= S_CMD_HOLD;
                    end
                end

                // Wait for the wire to return high before scoring the next bit.
                S_CMD_HOLD: begin
                    if (wire_lvl == 1'b1) begin
                        cmd_bit_idx <= cmd_bit_idx + 1'b1;
                        if (cmd_bit_idx == 4'd7) begin
                            // Got all 8 bits.  Decode.
                            // (cmd_sh already includes the bit just stored.)
                            if (cmd_sh == 8'h33) begin
                                tx_bit_idx <= 7'd0;
                                state      <= S_TX_WAIT;
                            end else begin
                                state <= S_IDLE;
                            end
                        end else begin
                            state <= S_CMD_WAIT;
                        end
                    end
                end

                // Wait for master to start a read slot.
                S_TX_WAIT: begin
                    if (wire_fall) begin
                        cnt <= {CW{1'b0}};
                        if (tx_bit_val == 1'b0) begin
                            owire_oeb <= 1'b0;     // hold low for 0
                            state     <= S_TX_DRIVE;
                        end else begin
                            owire_oeb <= 1'b1;     // leave high for 1
                            state     <= S_TX_HOLD;
                        end
                    end
                end

                S_TX_DRIVE: begin
                    if (cnt < C_READ_LOW[CW-1:0]) begin
                        cnt <= cnt + 1'b1;
                    end else begin
                        owire_oeb <= 1'b1;     // release
                        state     <= S_TX_HOLD;
                    end
                end

                S_TX_HOLD: begin
                    // Wait for the wire to come back high before the next slot.
                    if (wire_lvl == 1'b1) begin
                        if (tx_bit_idx == 7'd63) begin
                            state <= S_IDLE;
                        end else begin
                            tx_bit_idx <= tx_bit_idx + 1'b1;
                            state      <= S_TX_WAIT;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
