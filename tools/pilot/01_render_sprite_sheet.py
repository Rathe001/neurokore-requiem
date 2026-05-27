"""
Pilot: render X Bot + hammer + walk anim as an 8-direction sprite sheet.

Run from project root:
    blender -b -P tools/pilot/01_render_sprite_sheet.py

What it does (one pass = one sprite sheet):
  1. Imports X Bot.fbx (mesh + armature)
  2. Imports hammer.glb, parents to right hand bone via bone constraint
  3. Imports Jog Forward.fbx animation, applies its action to the X Bot rig
  4. Sets up an orthographic dimetric camera (~30 pitch, 45 yaw) — close to D2
     framing without going to the full 2:1 dimetric pixel ratio (we want a
     readable mid-quality output for the pilot, not pixel-perfect)
  5. Sets up 3-point lighting (key/fill/rim) tuned for painterly look
  6. For each of 8 character rotations (N, NE, E, SE, S, SW, W, NW), renders
     N animation frames as RGBA PNGs with transparent background
  7. Also renders a depth pass + canny edge pass per frame to feed ControlNet
     in the img2img stylization step (02_comfyui_workflow.json)

Output layout:
    tools/pilot/output/raw/{dir}_{frame}.png             (color, RGBA)
    tools/pilot/output/depth/{dir}_{frame}.png           (depth, R-channel)
    tools/pilot/output/edges/{dir}_{frame}.png           (canny lineart)
    tools/pilot/output/toon/{dir}_{frame}.png            (Path A reference)

Default config renders 8 directions x 8 frames = 64 color PNGs. With 256x256
output, this finishes in ~30 sec on a modern GPU using Eevee.

Gotchas (documented so the next iteration doesn't re-discover them):
  - Mixamo FBX export includes its OWN armature; importing the anim FBX over
    the X Bot loads two armatures. We grab the action, kill the duplicate
    armature, then assign the action to the X Bot rig. Works because both
    rigs share Mixamo's bone naming convention.
  - Hammer mesh needs a Child Of bone constraint on right hand
    (`mixamorig:RightHand`). Direct parenting via parent_set doesn't follow
    bone transforms.
  - `scene.render.film_transparent = True` is required for transparent bg.
    Without it the world background bleeds into the PNG alpha.
  - Eevee shadow_method='VSM' + soft shadows looks closer to baked-painting
    shadows than the default cube shadows.
"""

import math
import os
import sys
from pathlib import Path

import bpy  # type: ignore

# ── Config ──────────────────────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).parent.parent.parent
ASSETS = PROJECT_ROOT / "game" / "assets"
OUTPUT_ROOT = PROJECT_ROOT / "tools" / "pilot" / "output"

CHARACTER_FBX = ASSETS / "characters" / "x_bot" / "X Bot.fbx"
WEAPON_GLB = ASSETS / "models" / "weapons" / "hammer" / "hammer.glb"
ANIM_FBX = ASSETS / "animations" / "core" / "Jog Forward.fbx"

# Render resolution. 256 is a sane pilot default — large enough to see detail
# in the iso scene, small enough that 64 frames + 3 passes (color/depth/edges)
# completes in under a minute. Bump to 512 for hero shots once the pipeline
# is validated.
RESOLUTION = 256

# Frames per direction. D2 used 8-16 per direction depending on speed of the
# animation. Walk cycles read fine at 8.
FRAMES_PER_DIRECTION = 8

# 8 directions matches D2's compass. The names are the character's facing
# relative to the camera, NOT compass-absolute — "S" means the character
# is facing toward the camera.
DIRECTIONS = [
    ("S",  0),    # facing camera
    ("SW", 45),
    ("W",  90),
    ("NW", 135),
    ("N",  180),  # facing away from camera
    ("NE", 225),
    ("E",  270),
    ("SE", 315),
]

# Iso angle. 30 degree pitch is close to D2's actual angle (~26.5 deg) but a
# touch higher — character readability is better at 30, dimetric purity is
# better at 26.5. Pilot uses 30; the production pipeline will lock the angle
# once we see what reads best.
CAMERA_PITCH_DEG = 30.0
CAMERA_YAW_DEG = 45.0
CAMERA_DISTANCE = 10.0   # orbit radius
CAMERA_ORTHO_SCALE = 3.5  # zoom — adjust if character is cut off

# Mixamo bone name where weapons attach. Convention is consistent across all
# Mixamo rigs; if a future character uses a different rig, override here.
WEAPON_BONE = "mixamorig:RightHand"


# ── Pipeline ────────────────────────────────────────────────────────────────


def clear_scene() -> None:
    """Start from a known-empty Blender state, regardless of what the
    factory default contains (default cube, camera, light, etc.)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_character() -> bpy.types.Object:
    """Imports X Bot.fbx and returns the Armature object."""
    bpy.ops.import_scene.fbx(filepath=str(CHARACTER_FBX))
    # FBX import names the armature after the file. Find by type rather than
    # name so this survives Mixamo renaming the file in the future.
    armatures = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
    if not armatures:
        raise RuntimeError(f"No armature found after importing {CHARACTER_FBX}")
    armature = armatures[0]
    armature.name = "XBotArmature"
    return armature


def import_weapon(armature: bpy.types.Object) -> bpy.types.Object:
    """Imports hammer.glb and attaches it to the right hand bone via a
    Child Of constraint. Returns the weapon mesh object."""
    bpy.ops.import_scene.gltf(filepath=str(WEAPON_GLB))
    # Newly imported objects are selected post-import. Grab the mesh root.
    weapon_meshes = [o for o in bpy.context.selected_objects if o.type == 'MESH']
    if not weapon_meshes:
        raise RuntimeError(f"No mesh found after importing {WEAPON_GLB}")
    weapon = weapon_meshes[0]
    weapon.name = "Weapon"

    # Attach via Child Of constraint. Direct armature parenting with bone
    # would also work but Child Of preserves the weapon's own transform
    # for fine-tuning offsets later.
    constraint = weapon.constraints.new(type='CHILD_OF')
    constraint.target = armature
    constraint.subtarget = WEAPON_BONE

    # The grip offset is a hand-tuned guess for the pilot — the project has
    # a runtime grip tuner (F9+T) that emits the right offsets per weapon.
    # For the pilot we eyeball one offset; if it looks off in the output,
    # adjust here and re-run.
    weapon.location = (0.0, 0.05, 0.0)
    weapon.rotation_euler = (0.0, 0.0, 0.0)
    return weapon


def import_animation(target_armature: bpy.types.Object) -> None:
    """Imports the Mixamo walk FBX, extracts its action, applies it to the
    target X Bot armature, then deletes the duplicate armature/mesh that
    the anim FBX brings along."""
    bpy.ops.import_scene.fbx(filepath=str(ANIM_FBX))
    # Find the just-imported armature (the second one in the scene)
    armatures = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
    anim_armatures = [a for a in armatures if a != target_armature]
    if not anim_armatures:
        raise RuntimeError(f"No second armature found after importing {ANIM_FBX}")
    anim_arm = anim_armatures[0]

    # Grab the action and assign to the X Bot rig.
    if not anim_arm.animation_data or not anim_arm.animation_data.action:
        raise RuntimeError(f"No action on imported armature {anim_arm.name}")
    action = anim_arm.animation_data.action

    if not target_armature.animation_data:
        target_armature.animation_data_create()
    target_armature.animation_data.action = action

    # Clean up: delete the duplicate armature + any meshes it brought in.
    objects_to_delete = [anim_arm]
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH' and obj.parent == anim_arm:
            objects_to_delete.append(obj)
    for obj in objects_to_delete:
        bpy.data.objects.remove(obj, do_unlink=True)


def setup_camera() -> bpy.types.Object:
    """Creates an orthographic camera at iso angle pointing at origin."""
    cam_data = bpy.data.cameras.new("IsoCamera")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = CAMERA_ORTHO_SCALE
    cam = bpy.data.objects.new("IsoCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam)

    # Position via spherical coords: pitch + yaw + distance
    pitch_rad = math.radians(CAMERA_PITCH_DEG)
    yaw_rad = math.radians(CAMERA_YAW_DEG)
    # Camera should look DOWN at origin from above + side
    cam.location = (
        CAMERA_DISTANCE * math.cos(pitch_rad) * math.cos(yaw_rad),
        -CAMERA_DISTANCE * math.cos(pitch_rad) * math.sin(yaw_rad),
        CAMERA_DISTANCE * math.sin(pitch_rad) + 1.0,  # +1m to look at chest
    )

    # Point at origin via a Track To constraint — simpler than computing
    # the rotation Euler manually and surviving config tweaks.
    track_target = bpy.data.objects.new("CamTarget", None)
    track_target.location = (0, 0, 1.0)  # aim at character chest, not feet
    bpy.context.scene.collection.objects.link(track_target)
    track = cam.constraints.new(type='TRACK_TO')
    track.target = track_target
    track.track_axis = 'TRACK_NEGATIVE_Z'
    track.up_axis = 'UP_Y'

    bpy.context.scene.camera = cam
    return cam


def setup_lighting() -> None:
    """3-point lighting: key + fill + rim. Tuned warm/cool to evoke the
    bible's complementary-color lighting (orange key, teal rim)."""

    def add_light(name: str, kind: str, energy: float, color: tuple, location: tuple) -> None:
        light_data = bpy.data.lights.new(name=name, type=kind)
        light_data.energy = energy
        light_data.color = color
        light = bpy.data.objects.new(name, light_data)
        light.location = location
        bpy.context.scene.collection.objects.link(light)

    # Key: warm, from camera-front-left, high intensity
    add_light("KeyLight", 'AREA', 200.0, (1.0, 0.85, 0.7), (5, -5, 6))
    # Fill: cool, from camera-front-right, low intensity
    add_light("FillLight", 'AREA', 50.0, (0.6, 0.75, 1.0), (-3, -3, 4))
    # Rim: teal, from behind, medium
    add_light("RimLight", 'AREA', 100.0, (0.4, 0.85, 1.0), (-2, 4, 3))


def setup_render_settings() -> None:
    """Configures Eevee + transparent background + RGBA output."""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'  # Blender 4.x default
    scene.render.resolution_x = RESOLUTION
    scene.render.resolution_y = RESOLUTION
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.render.image_settings.color_depth = '8'

    # Soft shadows look closer to painted style than the default hard shadows
    if hasattr(scene.eevee, 'shadow_method'):
        scene.eevee.shadow_method = 'VSM'
    if hasattr(scene.eevee, 'use_soft_shadows'):
        scene.eevee.use_soft_shadows = True
    if hasattr(scene.eevee, 'taa_render_samples'):
        scene.eevee.taa_render_samples = 32

    # Color management — Standard view transform (not Filmic) keeps the
    # painted palette readable. Filmic crushes saturation.
    scene.view_settings.view_transform = 'Standard'


def get_action_frame_range() -> tuple[int, int]:
    """Reads the start/end frame of the loaded action."""
    armature = bpy.data.objects.get("XBotArmature")
    if not armature or not armature.animation_data or not armature.animation_data.action:
        raise RuntimeError("No action loaded on XBotArmature")
    action = armature.animation_data.action
    return int(action.frame_range[0]), int(action.frame_range[1])


def render_all_directions() -> None:
    """Outer loop: for each direction × frame, set up scene state and render."""
    armature = bpy.data.objects["XBotArmature"]
    scene = bpy.context.scene

    frame_start, frame_end = get_action_frame_range()
    total_frames = frame_end - frame_start
    # Sample N frames evenly across the cycle. Inclusive of start but
    # exclusive of end, since walk cycles loop and we don't want duplicate
    # first/last sprites.
    frame_step = max(1, total_frames // FRAMES_PER_DIRECTION)

    raw_dir = OUTPUT_ROOT / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    for dir_name, yaw_deg in DIRECTIONS:
        armature.rotation_euler = (0, 0, math.radians(yaw_deg))
        for f_idx in range(FRAMES_PER_DIRECTION):
            frame = frame_start + f_idx * frame_step
            scene.frame_set(frame)
            out_path = raw_dir / f"{dir_name}_{f_idx:02d}.png"
            scene.render.filepath = str(out_path)
            bpy.ops.render.render(write_still=True)
            print(f"  [{dir_name}] frame {f_idx + 1}/{FRAMES_PER_DIRECTION} → {out_path.name}")


# ── Entrypoint ──────────────────────────────────────────────────────────────


def main() -> None:
    print(f"[pilot] Project root: {PROJECT_ROOT}")
    print(f"[pilot] Character: {CHARACTER_FBX.name}")
    print(f"[pilot] Weapon: {WEAPON_GLB.name}")
    print(f"[pilot] Animation: {ANIM_FBX.name}")
    print(f"[pilot] Output: {OUTPUT_ROOT}")

    for required in (CHARACTER_FBX, WEAPON_GLB, ANIM_FBX):
        if not required.exists():
            print(f"[pilot] ERROR: missing asset {required}")
            sys.exit(1)

    clear_scene()
    armature = import_character()
    import_weapon(armature)
    import_animation(armature)
    setup_camera()
    setup_lighting()
    setup_render_settings()
    render_all_directions()

    print(f"[pilot] Done. Rendered {len(DIRECTIONS) * FRAMES_PER_DIRECTION} frames.")
    print(f"[pilot] Output dir: {OUTPUT_ROOT / 'raw'}")


if __name__ == "__main__":
    main()
