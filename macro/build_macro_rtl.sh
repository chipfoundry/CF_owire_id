#!/bin/sh
# Generate the macro's core copy: the released CF_owire_id core, renamed so
# it does not collide with the macro top (module CF_owire_id). The top and
# this copy are the only RTL the hardening flow reads.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
sed -e 's/^module CF_owire_id #(/module CF_owire_id_core #(/' \
    "$HERE/../rtl/CF_owire_id.v" > "$HERE/CF_owire_id_core.v"
grep -q '^module CF_owire_id_core #(' "$HERE/CF_owire_id_core.v"
echo "wrote $HERE/CF_owire_id_core.v"
