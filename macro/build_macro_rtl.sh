#!/bin/sh
# Generate the macro's RTL copies. The released core and the mux are used
# unchanged except for the core's module name:
#   CF_owire_id_core.v  the core (rtl/CF_owire_id.v), renamed so it does not
#                       collide with the macro top module CF_owire_id.
#   CF_owire_id_mux.v   the mux (rtl/CF_owire_id_mux.v, PR #1), with its core
#                       instance pointed at CF_owire_id_core.
# The hardening flow reads these two generated files plus CF_owire_id_top.v.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
RTL="$HERE/../rtl"
sed -e 's/^module CF_owire_id #(/module CF_owire_id_core #(/' \
    "$RTL/CF_owire_id.v" > "$HERE/CF_owire_id_core.v"
sed -e 's/^    CF_owire_id #($/    CF_owire_id_core #(/' \
    "$RTL/CF_owire_id_mux.v" > "$HERE/CF_owire_id_mux.v"
grep -q '^module CF_owire_id_core #(' "$HERE/CF_owire_id_core.v"
grep -q '^    CF_owire_id_core #($' "$HERE/CF_owire_id_mux.v"
grep -q '^module CF_owire_id_mux #(' "$HERE/CF_owire_id_mux.v"
echo "wrote $HERE/CF_owire_id_core.v and $HERE/CF_owire_id_mux.v"
