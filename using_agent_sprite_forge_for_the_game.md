# Using Agent Sprite Forge for this game

Sprite sheets for a unit are one video clip per action, cut into the horizontal strip the game already plays. The stills in `source_art/images/` are the master art. The pipeline does not redraw them.

## Keys and models

Both keys live in `~/.config/agent-sprite-forge/config.json` (mode `600`), which is outside the git repos.

- `GEMINI_API_KEY` is the Google key already stored there. It is used for images.
- `XAI_API_KEY` is the xAI key, stored in the same file. It is used for video.
- `models.gemini-image`, and the draft and hero slots, are `gemini-nano-banana-2.1` (Nano Banana 2.1).
- `models.xai-video`, and the draft and hero slots, are `grok-imagine-video-1.5`. Clips are requested at 480p.

Image edits, such as `master_still.py edit`, go to Nano Banana 2.1 first. Video goes to Grok Imagine Video 1.5. Do not put either key in a repo or in this file.

`grok-imagine-video-1.5` follows the still’s own shape, so clips are no longer padded out to 16:9 and cropped back. At 480p it also accepts a last frame. Idle and attack send the same still as the start frame and the end frame, which is what Agent Sprite Forge recommends so the clip returns to the pose. Move and die send the start frame only. Move is a walk cycle. Die is the `defeat` one-shot: the unit collapses and stays down, and the end pose is not pinned back to the still.

The priced estimate in the repo (`skills/generate2dmedia/references/prices.json`, checked 2026-10-06) is **$0.08 per second** at 480p plus **$0.01 per input image**. A pinned clip sends the still twice. A 5 second idle or attack is about $0.42. A 5 second move or die is about $0.41. The command prints the estimate and waits unless you pass `--yes`. `route_media.py` records the real charge.

## What each action is told

Idle is rewritten so the unit does not walk in place:

> standing still and only slightly breathing, no steps, no walking in place, feet planted.

The dragon profile adds that the wings stay nearly still and that it does not fly or step. The unit stays a ground character, so the pipeline does not switch idle to the flying hover template.

Die tells the model to collapse and stay lying down, without standing or walking again.

Attack styles in the profiles: the armored swordsman makes one sword swing and returns to the ready stance. The dragon makes one bite or claw, stays in place, and does not fly. Both return to the still because the end frame is pinned.

## One clip, even when a check fails

Each unit-action pair is one video and one spritesheet. `max_takes` is 1, so a failed automatic quality check does not generate another clip. The pipeline keeps every frame of that take and exports it. A failed video call (no clip at all) does not invent a sheet.

The plan folder is written once. A later run reuses `set_plan.json`, including its resolution and prompts, and it will not regenerate a clip that is already on disk. Delete `<unit>/_asf/set` before planning again if you need new wording or 480p on a unit that was planned earlier.

## Commands

From a shell, with the forge environment:

```bash
conda activate agent_sprite_forge
cd /home/rasmus/projects/agent_sprite_forge
```

Output for each action lands in:

`/home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/game_assets/AI_generated_sprites/blue_agent_sprite_forge/<unit>/<action>/`

That folder gets `spritesheet.png`, `spritesheet.json`, and `video.mp4`. Work files stay in `<unit>/_asf/`.

### Armored swordsman

All four actions, one clip each:

```bash
python -m rts_pipeline.generate_unit \
  --unit armored_swordsman \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/armored_swordsman/armored_swordsman.png \
  --profile rts_pipeline/profiles/armored_swordsman.json \
  --actions idle move attack die \
  --yes
```

A fresh unit can be planned as one action instead. Use one of these, or the all-four command. Do not run a second command to add an action the first plan left out.

Idle:

```bash
python -m rts_pipeline.generate_unit \
  --unit armored_swordsman \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/armored_swordsman/armored_swordsman.png \
  --profile rts_pipeline/profiles/armored_swordsman.json \
  --actions idle \
  --yes
```

Move:

```bash
python -m rts_pipeline.generate_unit \
  --unit armored_swordsman \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/armored_swordsman/armored_swordsman.png \
  --profile rts_pipeline/profiles/armored_swordsman.json \
  --actions move \
  --yes
```

Attack:

```bash
python -m rts_pipeline.generate_unit \
  --unit armored_swordsman \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/armored_swordsman/armored_swordsman.png \
  --profile rts_pipeline/profiles/armored_swordsman.json \
  --actions attack \
  --yes
```

Die:

```bash
python -m rts_pipeline.generate_unit \
  --unit armored_swordsman \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/armored_swordsman/armored_swordsman.png \
  --profile rts_pipeline/profiles/armored_swordsman.json \
  --actions die \
  --yes
```

### Dragon

The still is `source_art/images/blue/dragon_try2/dragon_try_2.png`. The unit id is `dragon_try2`.

```bash
python -m rts_pipeline.generate_unit \
  --unit dragon_try2 \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/dragon_try2/dragon_try_2.png \
  --profile rts_pipeline/profiles/dragon_try2.json \
  --actions idle move attack die \
  --yes
```

Same rule as the swordsman: one of these, or the all-four command, and only on a unit that does not already have a plan.

Idle:

```bash
python -m rts_pipeline.generate_unit \
  --unit dragon_try2 \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/dragon_try2/dragon_try_2.png \
  --profile rts_pipeline/profiles/dragon_try2.json \
  --actions idle \
  --yes
```

Move:

```bash
python -m rts_pipeline.generate_unit \
  --unit dragon_try2 \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/dragon_try2/dragon_try_2.png \
  --profile rts_pipeline/profiles/dragon_try2.json \
  --actions move \
  --yes
```

Attack:

```bash
python -m rts_pipeline.generate_unit \
  --unit dragon_try2 \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/dragon_try2/dragon_try_2.png \
  --profile rts_pipeline/profiles/dragon_try2.json \
  --actions attack \
  --yes
```

Die:

```bash
python -m rts_pipeline.generate_unit \
  --unit dragon_try2 \
  --image /home/rasmus/projects/godot_multiplayer_rts_developed_with_agent/source_art/images/blue/dragon_try2/dragon_try_2.png \
  --profile rts_pipeline/profiles/dragon_try2.json \
  --actions die \
  --yes
```

`--actions` on a unit that already has a plan only runs actions that were in that plan. The first command for a unit should list every action you want.

Profiles live in `rts_pipeline/profiles/`. `attack_style` is `sword` or `dragon`. The dragon profile’s `idle_extra` is the wing sentence above.
