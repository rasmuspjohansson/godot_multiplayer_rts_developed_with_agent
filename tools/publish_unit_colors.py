#!/usr/bin/env python3
"""Copy a unit's blue sheets into the team folders and recolor them.

Blue sheets are read from blue_agent_sprite_forge/<unit> when that folder has the action,
otherwise from AI_generated_sprites/blue/<unit>.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path("/home/rasmus/projects/sprite_sheet_generator")))
from change_colour import change_colour_file  # noqa: E402

ROOT = Path("/home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/game_assets/AI_generated_sprites")
FORGE = ROOT / "blue_agent_sprite_forge"
ACTIONS = ("idle", "move", "attack", "die")
ALL_COLORS = ("red", "green", "orange", "purple")


def publish(unit: str, colors: tuple[str, ...] = ALL_COLORS) -> None:
    src_root = FORGE / unit
    published = 0
    for action in ACTIONS:
        src = src_root / action / "spritesheet.png"
        if not src.is_file():
            src = ROOT / "blue" / unit / action / "spritesheet.png"
        if not src.is_file():
            print(f"MISSING {unit} {action}")
            continue
        blue_dir = ROOT / "blue" / unit / action
        blue_dir.mkdir(parents=True, exist_ok=True)
        blue_sheet = blue_dir / "spritesheet.png"
        if src.resolve() != blue_sheet.resolve():
            shutil.copy2(src, blue_sheet)
        manifest = src.parent / "spritesheet.json"
        data = json.loads(manifest.read_text()) if manifest.is_file() else {"action_id": action, "unit_type": unit}
        data["team_color"] = "blue"
        data["sprite_sheet"] = str(blue_sheet.resolve())
        (blue_dir / "spritesheet.json").write_text(json.dumps(data, indent=2) + "\n")
        for color in colors:
            out_dir = ROOT / color / unit / action
            out_dir.mkdir(parents=True, exist_ok=True)
            out_sheet = out_dir / "spritesheet.png"
            change_colour_file(str(blue_sheet), str(out_sheet), "blue", color)
            colored = dict(data)
            colored["team_color"] = color
            colored["sprite_sheet"] = str(out_sheet.resolve())
            colored["recolored_from"] = str(blue_sheet.resolve())
            (out_dir / "spritesheet.json").write_text(json.dumps(colored, indent=2) + "\n")
        published += 1
        print(f"published {unit} {action} -> {', '.join(colors)}")
    if published == 0:
        raise SystemExit(f"no sheets for {unit}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("units", nargs="+")
    ap.add_argument("--colors", nargs="+", default=list(ALL_COLORS))
    args = ap.parse_args()
    for unit in args.units:
        publish(unit, tuple(args.colors))


if __name__ == "__main__":
    main()
