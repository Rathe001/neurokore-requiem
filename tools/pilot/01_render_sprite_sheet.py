"""
Pilot: render an AI-generated (or any) rigged + animated .glb character
as an 8-direction iso sprite sheet, with NO AI stylization step.

The character's painted look lives in its baked textures — identity is
locked across all 8 directions because they're all renders of the same
mesh. This is the deliberate replacement for the SDXL+IPAdapter pipeline
that hit the identity-drift wall in earlier iterations.

Run from project root:
    blender -b -P tools/pilot/01_render_sprite_sheet.py

What it does:
  1. Imports a .glb with mesh + armature + multiple baked actions
     (Meshy's "Merged Animations" output is the canonical input)
  2. Auto-centers + auto-scales the mesh to fit the iso camera frame
  3. Sets up an orthographic dimetric camera (30 pitch, 45 yaw)
  4. Sets up 3-point lighting (warm key / cool fill / teal rim)
  5. For each (animation, direction, frame) triple, renders an RGBA PNG
     into output/raw/<character>/<animation>/<dir>_<frame>.png

Notes:
  - `scene.render.film_transparent = True` is required for transparent bg
  - Some Meshy/Tripo exports have non-standard orientation/scale —
    auto-center + bbox-based scale handle this generically
  - Animations with baked root motion (Walking, Running) translate the
    character across frames; RECENTER_PER_FRAME re-anchors the hip to
    origin each frame so the character stays in-frame.
"""

import math
import sys
from pathlib import Path

import bpy  # type: ignore

# ── Config ──────────────────────────────────────────────────────────────────

PROJECT_ROOT = Path(__file__).parent.parent.parent
OUTPUT_ROOT = PROJECT_ROOT / "tools" / "pilot" / "output"

# Character. `glb` should be the Meshy "Merged Animations" output — the
# one with all actions baked into a single file. `animations` lists
# (output_slug, action_name_in_glb, frames_to_sample) triples; only the
# actions listed here are rendered, so it doubles as a filter.
CHARACTER = {
    "name": "crimson_vein_titan",
    "glb": Path.home() / "Desktop" / "crimson_vein_titan"
            / "Meshy_AI_Crimson_Vein_Titan_biped"
            / "Meshy_AI_Crimson_Vein_Titan_biped_Meshy_AI_Meshy_Merged_Animations.glb",
    "animations": [
        # (output slug, blender action name,                 frames sampled per dir)
        ("idle",  "Idle_5",                                   6),
        ("walk",  "Walking",                                 12),
        ("cast",  "mage_soell_cast_3",                        8),
        ("hit",   "Hit_Reaction_1",                          10),
        ("death", "Dead",                                    12),
    ],
}

# Auto-scale target height in meters. Meshy/Tripo exports come at
# arbitrary scales — we measure the imported mesh's Z extent and scale
# it to this height before rendering, so the camera frame is always
# consistent regardless of source.
TARGET_CHARACTER_HEIGHT = 1.8

# Render resolution. 256 is a sane pilot default — large enough to see detail
# in the iso scene, small enough that a full batch completes in a couple of
# minutes. Bump to 512 for hero shots once the pipeline is validated.
RESOLUTION = 256

# Re-anchor the hip bone to world origin each frame. Walk/run animations
# typically have root motion baked in; without re-anchoring, the character
# slides out of frame across the sampled frames.
RECENTER_PER_FRAME = True

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

# Base yaw offset to reconcile Meshy's default +Y forward with our
# "S = facing camera" convention. Confirmed at 180° for the Ironclad
# Enforcer — likely the same for any Meshy export.
BASE_YAW_DEG = 180.0

# Iso angle. 30 degree pitch is close to D2's actual angle (~26.5 deg) but a
# touch higher — character readability is better at 30, dimetric purity is
# better at 26.5. Pilot uses 30; the production pipeline will lock the angle
# once we see what reads best.
CAMERA_PITCH_DEG = 30.0
CAMERA_YAW_DEG = 45.0
CAMERA_DISTANCE = 10.0
CAMERA_ORTHO_SCALE = 2.5

# ── Pipeline ────────────────────────────────────────────────────────────────


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_character(glb_path: Path) -> tuple[bpy.types.Object, bpy.types.Object | None]:
    """Imports a rigged + textured .glb. Auto-centers at origin, auto-scales
    to TARGET_CHARACTER_HEIGHT. Returns (wrapper Empty, armature object).
    The wrapper is the yaw rotation handle; the armature is what we
    assign actions to."""
    import mathutils  # type: ignore

    bpy.ops.import_scene.gltf(filepath=str(glb_path))
    imported = list(bpy.context.selected_objects)
    if not imported:
        raise RuntimeError(f"No objects imported from {glb_path}")

    armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)

    # World-space bbox across all imported meshes (used for scale/center).
    min_x = min_y = min_z = float("inf")
    max_x = max_y = max_z = float("-inf")
    for obj in imported:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            wc = obj.matrix_world @ mathutils.Vector(corner)
            min_x, max_x = min(min_x, wc.x), max(max_x, wc.x)
            min_y, max_y = min(min_y, wc.y), max(max_y, wc.y)
            min_z, max_z = min(min_z, wc.z), max(max_z, wc.z)

    width, depth, height = max_x - min_x, max_y - min_y, max_z - min_z
    print(f"[pilot] Imported bbox: X={width:.3f} Y={depth:.3f} Z={height:.3f}")

    wrapper = bpy.data.objects.new("CharacterWrapper", None)
    bpy.context.scene.collection.objects.link(wrapper)
    for obj in imported:
        if obj.parent is None:
            obj.parent = wrapper

    tallest_axis = max(width, depth, height)
    scale_factor = TARGET_CHARACTER_HEIGHT / tallest_axis if tallest_axis > 0 else 1.0
    wrapper.scale = (scale_factor, scale_factor, scale_factor)
    print(f"[pilot] Scale factor: {scale_factor:.4f}")

    feet_offset_z = min_z * scale_factor
    wrapper.location = (
        -(min_x + width / 2) * scale_factor,
        -(min_y + depth / 2) * scale_factor,
        -feet_offset_z,
    )

    bpy.context.view_layer.update()
    return wrapper, armature


def assign_action(armature: bpy.types.Object, action_name: str) -> bpy.types.Action:
    """Assigns a named action from bpy.data.actions to the armature's
    animation_data and returns it."""
    if armature is None:
        raise RuntimeError("No armature in scene — character is not rigged")
    if action_name not in bpy.data.actions:
        available = [a.name for a in bpy.data.actions]
        raise RuntimeError(
            f"Action {action_name!r} not in glb. Available: {available}"
        )
    action = bpy.data.actions[action_name]
    if armature.animation_data is None:
        armature.animation_data_create()
    armature.animation_data.action = action
    return action


def sample_frame_indices(action: bpy.types.Action, count: int) -> list[int]:
    """Evenly-spaced frame indices across an action's range. The last
    frame is included only if count > 1, to avoid duplicating the loop
    point on looping animations (idle/walk/run end where they start)."""
    start = int(action.frame_range[0])
    end = int(action.frame_range[1])
    span = max(end - start, 1)
    if count <= 1:
        return [start]
    step = span / count
    return [int(round(start + i * step)) for i in range(count)]


def recenter_hip_to_origin(
    wrapper: bpy.types.Object, armature: bpy.types.Object
) -> None:
    """After scene.frame_set, the bone transforms have updated. Compute
    the Hips bone world position and shift the wrapper so that XY=0
    (Z is left alone — feet stay on the ground)."""
    if armature is None or "Hips" not in armature.pose.bones:
        return
    hip = armature.pose.bones["Hips"]
    # Bone matrix is in armature local space; multiply by armature world
    # matrix (which includes wrapper transform) to get world.
    hip_world = armature.matrix_world @ hip.matrix.translation
    wrapper.location.x -= hip_world.x
    wrapper.location.y -= hip_world.y
    bpy.context.view_layer.update()


def setup_camera() -> bpy.types.Object:
    cam_data = bpy.data.cameras.new("IsoCamera")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = CAMERA_ORTHO_SCALE
    cam = bpy.data.objects.new("IsoCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam)

    pitch_rad = math.radians(CAMERA_PITCH_DEG)
    yaw_rad = math.radians(CAMERA_YAW_DEG)
    cam.location = (
        CAMERA_DISTANCE * math.cos(pitch_rad) * math.cos(yaw_rad),
        -CAMERA_DISTANCE * math.cos(pitch_rad) * math.sin(yaw_rad),
        CAMERA_DISTANCE * math.sin(pitch_rad) + 1.0,
    )

    track_target = bpy.data.objects.new("CamTarget", None)
    track_target.location = (0, 0, 1.0)
    bpy.context.scene.collection.objects.link(track_target)
    track = cam.constraints.new(type="TRACK_TO")
    track.target = track_target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"

    bpy.context.scene.camera = cam
    return cam


def setup_lighting() -> None:
    def add_light(name, kind, energy, color, location):
        ld = bpy.data.lights.new(name=name, type=kind)
        ld.energy = energy
        ld.color = color
        light = bpy.data.objects.new(name, ld)
        light.location = location
        bpy.context.scene.collection.objects.link(light)

    add_light("KeyLight",  "AREA", 400.0, (1.0, 0.85, 0.7),  (5, -5, 6))
    add_light("FillLight", "AREA", 100.0, (0.6, 0.75, 1.0), (-3, -3, 4))
    add_light("RimLight",  "AREA", 200.0, (0.4, 0.85, 1.0), (-2,  4, 3))


def setup_render_settings() -> None:
    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties["engine"].enum_items.keys()
    if "BLENDER_EEVEE" in engines:
        scene.render.engine = "BLENDER_EEVEE"
    elif "BLENDER_EEVEE_NEXT" in engines:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    else:
        scene.render.engine = "CYCLES"
    scene.render.resolution_x = RESOLUTION
    scene.render.resolution_y = RESOLUTION
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"

    if hasattr(scene.eevee, "shadow_method"):
        scene.eevee.shadow_method = "VSM"
    if hasattr(scene.eevee, "use_soft_shadows"):
        scene.eevee.use_soft_shadows = True
    if hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = 32
    scene.view_settings.view_transform = "Standard"


def render_character(
    wrapper: bpy.types.Object, armature: bpy.types.Object
) -> int:
    """Outer loop: animations × directions × frames. Returns total frame
    count written."""
    scene = bpy.context.scene
    char_name = CHARACTER["name"]
    char_root = OUTPUT_ROOT / "raw" / char_name
    char_root.mkdir(parents=True, exist_ok=True)

    # Capture the wrapper's auto-computed XY home so we can reset it
    # between frames before re-centering on hip.
    home_xy = (wrapper.location.x, wrapper.location.y)

    total = 0
    for slug, action_name, frame_count in CHARACTER["animations"]:
        action = assign_action(armature, action_name)
        sampled = sample_frame_indices(action, frame_count)
        out_dir = char_root / slug
        out_dir.mkdir(parents=True, exist_ok=True)
        print(f"[pilot] {slug}: action {action_name!r} sampling {sampled}")

        for dir_name, yaw_deg in DIRECTIONS:
            wrapper.rotation_euler = (0, 0, math.radians(yaw_deg + BASE_YAW_DEG))

            for f_idx, frame in enumerate(sampled):
                # Reset wrapper XY before re-centering so successive frames
                # don't accumulate offset drift.
                wrapper.location.x, wrapper.location.y = home_xy
                scene.frame_set(frame)
                if RECENTER_PER_FRAME:
                    recenter_hip_to_origin(wrapper, armature)

                out_path = out_dir / f"{dir_name}_{f_idx:02d}.png"
                scene.render.filepath = str(out_path)
                bpy.ops.render.render(write_still=True)
                total += 1
            print(f"  [{slug}] [{dir_name}] {len(sampled)} frames written")

    return total


# ── Entrypoint ──────────────────────────────────────────────────────────────


def main() -> None:
    glb = CHARACTER["glb"]
    print(f"[pilot] Character: {CHARACTER['name']}")
    print(f"[pilot] Source glb: {glb}")
    print(f"[pilot] Output:    {OUTPUT_ROOT / 'raw' / CHARACTER['name']}")

    if not glb.exists():
        print(f"[pilot] ERROR: missing character glb {glb}")
        sys.exit(1)

    clear_scene()
    wrapper, armature = import_character(glb)
    if armature is None:
        print("[pilot] ERROR: glb has no armature — needs rigged + animated source")
        sys.exit(1)
    print(f"[pilot] Armature: {armature.name} ({len(armature.pose.bones)} bones)")
    print(f"[pilot] Actions in glb: {[a.name for a in bpy.data.actions]}")

    setup_camera()
    setup_lighting()
    setup_render_settings()
    total = render_character(wrapper, armature)

    print(f"[pilot] Done. {total} frames rendered.")
    print(f"[pilot] Output dir: {OUTPUT_ROOT / 'raw' / CHARACTER['name']}")


if __name__ == "__main__":
    main()
