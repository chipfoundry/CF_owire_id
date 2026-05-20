# Standalone iverilog runner for the CF_owire_id testbench.
#
# Targets:
#   make sim   -- compile + run, prints PASS/FAIL on the last line
#   make vcd   -- same, then opens the waveform in gtkwave
#   make clean -- remove build artefacts

RTL_DIR := ../rtl
SRC     := $(RTL_DIR)/CF_owire_id.v tb_CF_owire_id.v
VVP     := tb_CF_owire_id.vvp
VCD     := tb_CF_owire_id.vcd

IVERILOG ?= iverilog
VVP_BIN  ?= vvp
GTKWAVE  ?= gtkwave

IVERILOG_FLAGS := -g2012 -Wall -DIVERILOG_SIM

.PHONY: sim vcd clean

sim: $(VVP)
	$(VVP_BIN) $(VVP)

vcd: sim
	$(GTKWAVE) $(VCD) &

$(VVP): $(SRC)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(SRC)

clean:
	rm -f $(VVP) $(VCD)
