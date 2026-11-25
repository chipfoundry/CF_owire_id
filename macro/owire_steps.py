"""Custom LibreLane steps for the CF_owire_id macro flow.

Registers:
  * ``OwireMacro.PowerStubBridge`` -- after global routing; draws met1 special
    bridges from the placeholder VPWR / VGND stubs onto the standard-cell
    rails of the same net. The stubs sit at y 228..229.5 (VPWR) and 232.5..234
    (VGND), which the row grid does not put on same-net rails, so the bridge
    is needed for the macro to be powered. Detailed routing avoids special
    shapes, so it runs after this step.
"""

import os

from librelane.steps import Step
from librelane.steps.odb import OdbpyStep


@Step.factory.register()
class PowerStubBridge(OdbpyStep):
    id = "OwireMacro.PowerStubBridge"
    name = "Bridge the placeholder VPWR/VGND stubs onto same-net met1 rails"

    def get_script_path(self):
        return os.path.join(os.path.dirname(__file__), "power_stub_bridge.py")
