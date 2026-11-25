#!/usr/bin/env python3
"""Entry point: registers the CF_owire_id macro steps, then runs LibreLane."""
import owire_steps  # noqa: F401  -- registers OwireMacro.* steps
from librelane.__main__ import cli

if __name__ == "__main__":
    cli()
