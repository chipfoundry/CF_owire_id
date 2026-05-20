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
#
# Both pad wrappers depend on CF_owire_id.v.  Keep all three unless you
# have a strong reason to instantiate the core directly; the wrappers are
# the supported integration path for OpenFrame designs.

rtl/CF_owire_id.v
rtl/CF_owire_id_pad.v
rtl/CF_owire_id_shared.v
