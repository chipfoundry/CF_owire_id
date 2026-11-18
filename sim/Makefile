# Standalone iverilog runner for the CF_owire_id testbench.
#
# Targets:
#   make sim   -- compile + run, prints PASS/FAIL on the last line
#   make vcd   -- same, then opens the waveform in gtkwave
#   make clean -- remove build artefacts

RTL_DIR := ../rtl
SRC     := $(RTL_DIR)/CF_owire_id.v tb_CF_owire_id.v
MUX_SRC := $(RTL_DIR)/CF_owire_id.v $(RTL_DIR)/CF_owire_id_mux.v tb_CF_owire_id_mux.v
VVP     := tb_CF_owire_id.vvp
MUX_VVP := tb_CF_owire_id_mux.vvp
VCD     := tb_CF_owire_id.vcd

IVERILOG ?= iverilog
VVP_BIN  ?= vvp
GTKWAVE  ?= gtkwave

IVERILOG_FLAGS := -g2012 -Wall -DIVERILOG_SIM

.PHONY: sim vcd clean

sim: $(VVP) $(MUX_VVP)
	$(VVP_BIN) $(VVP)
	$(VVP_BIN) $(MUX_VVP)

vcd: sim
	$(GTKWAVE) $(VCD) &

$(VVP): $(SRC)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(SRC)

$(MUX_VVP): $(MUX_SRC)
	$(IVERILOG) $(IVERILOG_FLAGS) -o $@ $(MUX_SRC)

clean:
	rm -f $(VVP) $(MUX_VVP) $(VCD) tb_CF_owire_id_mux.vcd
