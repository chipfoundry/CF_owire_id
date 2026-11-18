# CF_owire_id filelist
#
# Include this file in your OpenFrame project's build flow.
#
# iverilog:   iverilog -g2012 -f /path/to/CF_owire_id/filelist.f ...
# verilator:  verilator -f /path/to/CF_owire_id/filelist.f ...
#
# Files:
#   - CF_owire_id.v          Dallas/Maxim 1-Wire slave core (always needed).
#                            Includes its own behavioural ring oscillator
#                            for simulation; for synthesis, replace the
#                            placeholder inverter ring under `ifdef SYNTHESIS
#                            with PDK-keep-attribute cells (e.g. sky130
#                            sky130_fd_sc_hd__inv_2 instances).
#   - CF_owire_id_pad.v      OpenFrame pad wrapper, dedicated-pin use.
#   - CF_owire_id_shared.v   OpenFrame pad wrapper, shared-pin (open-drain
#                            co-use) for cases where the ID pin is also
#                            driven by user logic.
#   - CF_owire_id_mux.v      Pad mux. While chip_reset_n is low the slave
#                            owns the pin (dm=010) and can answer a 1-Wire
#                            read. While chip_reset_n is high the user's
#                            pad controls pass through and the slave is
#                            held in reset.
#
# The wrappers depend on CF_owire_id.v.

rtl/CF_owire_id.v
rtl/CF_owire_id_pad.v
rtl/CF_owire_id_shared.v
rtl/CF_owire_id_mux.v
