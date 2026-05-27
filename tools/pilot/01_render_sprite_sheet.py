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

# Animation pilot: DISABLED for first pass.
#
# Mixamo's cross-FBX animation pipeline relies on bone-axis-correction
# retargeting (Godot does this via SkeletonProfileHumanoid + BoneMap;
# Blender requires an addon like Rokoko Studio Live or Auto Rig Pro).
# Without retargeting, applying an action from one Mixamo FBX onto a
# rest-pose armature from another Mixamo FBX produces a contorted result
# (we saw the character render horizontal-running-pose despite both
# armatures sharing identical bone names).
#
# For the pilot, we render T-pose only — that's enough to validate the
# rest of the pipeline (camera angle, lighting, weapon attachment,
# sprite-sheet output, ComfyUI img2img). Animation retargeting will be
# solved as a separate step.
ANIM_FBX = None  # ASSETS / "animations" / "core" / "Idle.fbx"

# Render resolution. 256 is a sane pilot default — large enough to see detail
# in the iso scene, small enough that 64 frames + 3 passes (color/depth/edges)
# completes in under a minute. Bump to 512 for hero shots once the pipeline
# is validated.
RESOLUTION = 256

# Frames per direction. D2 used 8-16 per direction depending on speed of the
# animation. Walk cycles read fine at 8. With ANIM_FBX disabled, we collapse
# to 1 frame (T-pose) per direction.
FRAMES_PER_DIRECTION = 1 if True else 8  # toggle by setting ANIM_FBX

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
CAMERA_ORTHO_SCALE = 2.5  # zoom — smaller = closer; 2.5m wide fits a 1.8m char

# Mixamo bone name where weapons attach. Convention is consistent across all
# Mixamo rigs; if a future character uses a different rig, override here.
WEAPON_BONE = "mixamorig:RightHand"


# ── Pipeline ────────────────────────────────────────────────────────────────


def clear_scene() -> None:
    """Start from a known-empty Blender state, regardless of what the
    factory default contains (default cube, camera, light, etc.)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_character_and_anim() -> bpy.types.Object:
    """Imports X Bot.fbx (mesh + armature). Pilot v1 does NOT apply
    animation — see ANIM_FBX comment at top of file for why.

    Returns the armature object."""
    import mathutils  # type: ignore

    bpy.ops.import_scene.fbx(filepath=str(CHARACTER_FBX))
    armatures = [o for o in bpy.context.scene.objects if o.type == 'ARMATURE']
    if not armatures:
        raise RuntimeError(f"No armature in {CHARACTER_FBX}")
    armature = armatures[0]
    armature.name = "AnimArmature"  # name kept for compatibility with rest of script

    # Diagnostic bbox of all mesh children.
    min_x = min_y = min_z = float('inf')
    max_x = max_y = max_z = float('-inf')
    for child in armature.children_recursive:
        if child.type != 'MESH':
            continue
        for corner in child.bound_box:
            world_corner = child.matrix_world @ mathutils.Vector(corner)
            min_x, max_x = min(min_x, world_corner.x), max(max_x, world_corner.x)
            min_y, max_y = min(min_y, world_corner.y), max(max_y, world_corner.y)
            min_z, max_z = min(min_z, world_corner.z), max(max_z, world_corner.z)
    print(f"[pilot] Character bbox (world, T-pose):")
    print(f"[pilot]   X: [{min_x:.3f}, {max_x:.3f}] = {max_x - min_x:.3f}m wide")
    print(f"[pilot]   Z: [{min_z:.3f}, {max_z:.3f}] = {max_z - min_z:.3f}m tall")

    return armature


def import_weapon(armature: bpy.types.Object) -> bpy.types.Object:
    """Imports hammer.glb and parents it to the right hand bone.

    Uses the `parent_set` operator with type='BONE' rather than a Child Of
    constraint — the operator handles `matrix_parent_inverse` calculation
    automatically, where the constraint API doesn't and the weapon ends up
    at the wrong world position.
    """
    bpy.ops.import_scene.gltf(filepath=str(WEAPON_GLB))
    weapon_meshes = [o for o in bpy.context.selected_objects if o.type == 'MESH']
    if not weapon_meshes:
        raise RuntimeError(f"No mesh found after importing {WEAPON_GLB}")
    # GLB imports often include child meshes — collect them all so they
    # parent as a group.
    weapon_roots = [o for o in bpy.context.selected_objects
                    if o.type in ('MESH', 'EMPTY') and o.parent is None]
    if weapon_roots:
        weapon_meshes = weapon_roots
    weapon = weapon_meshes[0]
    weapon.name = "Weapon"

    # parent_set operates on the current selection: select weapons, then the
    # armature (last = active), then call parent_set with type='BONE' after
    # making the desired bone the active bone of the armature.
    bpy.ops.object.select_all(action='DESELECT')
    for w in weapon_meshes:
        w.select_set(True)
    armature.select_set(True)
    bpy.context.view_layer.objects.active = armature
    armature.data.bones.active = armature.data.bones.get(WEAPON_BONE)
    if armature.data.bones.active is None:
        raise RuntimeError(
            f"Bone {WEAPON_BONE!r} not found on armature. "
            f"Bones: {[b.name for b in armature.data.bones][:6]}..."
        )
    bpy.ops.object.parent_set(type='BONE')

    # Eyeball grip offset for the pilot. The project's runtime weapon-grip
    # tuner (F9+T) emits the canonical offsets per weapon — those values
    # are in `game/scripts/.../weapon_grips.gd` and can be cross-walked
    # here once the pilot is locked.
    weapon.location = (0.0, 0.0, 0.0)
    weapon.rotation_euler = (0.0, 0.0, 0.0)
    return weapon


def verify_animation_loaded(armature: bpy.types.Object) -> None:
    """Pilot v1 renders T-pose only — no action to verify."""
    if ANIM_FBX is None:
        print("[pilot] Animation disabled (T-pose render). See ANIM_FBX comment.")
        return
    if not armature.animation_data or not armature.animation_data.action:
        raise RuntimeError(f"No action attached to {armature.name}")
    action = armature.animation_data.action
    print(f"[pilot] Action: {action.name}, frames {int(action.frame_range[0])}-{int(action.frame_range[1])}")


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

    # Bumped 2x from initial; second iteration with 4x went pure white,
    # so back off to a middle value.
    # Key: warm, from camera-front-left
    add_light("KeyLight", 'AREA', 400.0, (1.0, 0.85, 0.7), (5, -5, 6))
    # Fill: cool, from camera-front-right
    add_light("FillLight", 'AREA', 100.0, (0.6, 0.75, 1.0), (-3, -3, 4))
    # Rim: teal, from behind
    add_light("RimLight", 'AREA', 200.0, (0.4, 0.85, 1.0), (-2, 4, 3))


def setup_render_settings() -> None:
    """Configures Eevee + transparent background + RGBA output."""
    scene = bpy.context.scene
    # In Blender 4.2-4.5 the engine was 'BLENDER_EEVEE_NEXT'; in 5.x it was
    # renamed back to 'BLENDER_EEVEE' (the old Eevee was removed). Try the
    # 5.x name first, fall back to NEXT for 4.x compatibility.
    available_engines = scene.render.bl_rna.properties['engine'].enum_items.keys()
    if 'BLENDER_EEVEE' in available_engines:
        scene.render.engine = 'BLENDER_EEVEE'
    elif 'BLENDER_EEVEE_NEXT' in available_engines:
        scene.render.engine = 'BLENDER_EEVEE_NEXT'
    else:
        scene.render.engine = 'CYCLES'  # absolute fallback
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


def render_all_directions() -> None:
    """Outer loop: for each direction × frame, set up scene state and render.
    When ANIM_FBX is None, renders T-pose only (1 frame per direction)."""
    armature = bpy.data.objects["AnimArmature"]
    scene = bpy.context.scene

    raw_dir = OUTPUT_ROOT / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    # Save the armature's import-time rotation (Mixamo's auto-rotation puts
    # it at +90°X to stand the character up in Blender's Z-up). Direction
    # yaw is layered ON TOP of that base rotation, not replacing it.
    base_rotation = armature.rotation_euler.copy()

    for dir_name, yaw_deg in DIRECTIONS:
        # Preserve the import-time X rotation; only override the Z yaw.
        armature.rotation_euler = (base_rotation.x, base_rotation.y, math.radians(yaw_deg))

        for f_idx in range(FRAMES_PER_DIRECTION):
            # If we have an action, sample evenly across its frame range.
            # If not, just render at frame 1 (T-pose / rest).
            if ANIM_FBX is not None and armature.animation_data \
                    and armature.animation_data.action:
                action = armature.animation_data.action
                frame_start, frame_end = int(action.frame_range[0]), int(action.frame_range[1])
                total = frame_end - frame_start
                step = max(1, total // FRAMES_PER_DIRECTION)
                frame = frame_start + f_idx * step
            else:
                frame = 1
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
    print(f"[pilot] Animation: {ANIM_FBX.name if ANIM_FBX else '(disabled — T-pose only)'}")
    print(f"[pilot] Output: {OUTPUT_ROOT}")

    required_assets = [CHARACTER_FBX, WEAPON_GLB]
    if ANIM_FBX is not None:
        required_assets.append(ANIM_FBX)
    for required in required_assets:
        if not required.exists():
            print(f"[pilot] ERROR: missing asset {required}")
            sys.exit(1)

    clear_scene()
    armature = import_character_and_anim()
    verify_animation_loaded(armature)
    import_weapon(armature)
    setup_camera()
    setup_lighting()
    setup_render_settings()
    render_all_directions()

    print(f"[pilot] Done. Rendered {len(DIRECTIONS) * FRAMES_PER_DIRECTION} frames.")
    print(f"[pilot] Output dir: {OUTPUT_ROOT / 'raw'}")


if __name__ == "__main__":
    main()
