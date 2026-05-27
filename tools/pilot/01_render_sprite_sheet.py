"""
Pilot: render an AI-generated (or any) .glb character as an 8-direction
iso sprite sheet, with NO AI stylization step.

The character's painted look lives in its baked textures — identity is
locked across all 8 directions because they're all renders of the same
mesh. This is the deliberate replacement for the SDXL+IPAdapter pipeline
that hit the identity-drift wall in earlier iterations.

Run from project root:
    blender -b -P tools/pilot/01_render_sprite_sheet.py

What it does:
  1. Imports a .glb (Meshy / Tripo / Hunyuan output, or any textured GLB)
  2. Auto-centers + auto-scales the mesh to fit the iso camera frame
  3. Sets up an orthographic dimetric camera (30 pitch, 45 yaw)
  4. Sets up 3-point lighting (warm key / cool fill / teal rim)
  5. For each of 8 character rotations (S, SW, W, NW, N, NE, E, SE),
     renders one frame as an RGBA PNG with transparent background

Output:
    tools/pilot/output/raw/{dir}_00.png      (RGBA, 256x256 by default)

Default config renders 8 directions × 1 frame = 8 PNGs in ~5 sec.
Add animation frames later by setting FRAMES_PER_DIRECTION > 1 once
the model has a rigged + animated armature.

Notes:
  - `scene.render.film_transparent = True` is required for transparent bg
  - Some Meshy/Tripo exports have non-standard orientation/scale —
    auto-center + bbox-based scale handle this generically
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

# Source character. Path to any .glb (AI-generated from Meshy/Tripo/
# Hunyuan, or hand-modeled). Texture is baked into the mesh; we render
# the painted look directly — no SDXL stylization step.
CHARACTER_GLB = Path.home() / "Desktop" / "Meshy_AI_Ironclad_Enforcer_0527171205_texture.glb"

# Auto-scale target height in meters. Meshy/Tripo exports come at
# arbitrary scales — we measure the imported mesh's Z extent and scale
# it to this height before rendering, so the camera frame is always
# consistent regardless of source.
TARGET_CHARACTER_HEIGHT = 1.8

# Render resolution. 256 is a sane pilot default — large enough to see detail
# in the iso scene, small enough that 64 frames + 3 passes (color/depth/edges)
# completes in under a minute. Bump to 512 for hero shots once the pipeline
# is validated.
RESOLUTION = 256

# Frames per direction. With a static-pose model (Meshy default A-pose
# or T-pose), this is 1. With a rigged+animated model, bump to 8-16 to
# sample frames evenly across the animation.
FRAMES_PER_DIRECTION = 1

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

# ── Pipeline ────────────────────────────────────────────────────────────────


def clear_scene() -> None:
    """Start from a known-empty Blender state, regardless of what the
    factory default contains (default cube, camera, light, etc.)."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_character() -> bpy.types.Object:
    """Imports a .glb character. Auto-centers at origin, auto-scales to
    TARGET_CHARACTER_HEIGHT.

    Returns the root Empty/Mesh object that all directions rotate around.
    For an unrigged Meshy export this is typically a top-level Empty
    containing one or more Mesh children. We create a wrapper Empty so
    the direction yaw rotation always has a clean parent regardless of
    what structure the .glb produced."""
    import mathutils  # type: ignore

    bpy.ops.import_scene.gltf(filepath=str(CHARACTER_GLB))

    # Collect every object the import created (selected post-import).
    imported = [o for o in bpy.context.selected_objects]
    if not imported:
        raise RuntimeError(f"No objects imported from {CHARACTER_GLB}")

    # Compute world-space bbox across all imported meshes
    min_x = min_y = min_z = float('inf')
    max_x = max_y = max_z = float('-inf')
    for obj in imported:
        if obj.type != 'MESH':
            continue
        for corner in obj.bound_box:
            world_corner = obj.matrix_world @ mathutils.Vector(corner)
            min_x, max_x = min(min_x, world_corner.x), max(max_x, world_corner.x)
            min_y, max_y = min(min_y, world_corner.y), max(max_y, world_corner.y)
            min_z, max_z = min(min_z, world_corner.z), max(max_z, world_corner.z)

    width, depth, height = max_x - min_x, max_y - min_y, max_z - min_z
    print(f"[pilot] Imported bbox (raw):")
    print(f"[pilot]   X: [{min_x:.3f}, {max_x:.3f}] = {width:.3f}m")
    print(f"[pilot]   Y: [{min_y:.3f}, {max_y:.3f}] = {depth:.3f}m")
    print(f"[pilot]   Z: [{min_z:.3f}, {max_z:.3f}] = {height:.3f}m")

    # Create a wrapper Empty at world origin. Parent all imported roots to
    # it. The Empty becomes our single rotation handle — yawing it
    # rotates the whole character set as one unit.
    wrapper = bpy.data.objects.new("CharacterWrapper", None)
    bpy.context.scene.collection.objects.link(wrapper)
    for obj in imported:
        if obj.parent is None:
            obj.parent = wrapper

    # Scale to target height. If the mesh is upside-down or sideways
    # (some Meshy exports have unusual axes), the height we measure is
    # along world Z — we scale uniformly so whichever axis IS the tall
    # one ends up matching TARGET_CHARACTER_HEIGHT.
    tallest_axis = max(width, depth, height)
    if tallest_axis > 0:
        scale_factor = TARGET_CHARACTER_HEIGHT / tallest_axis
        wrapper.scale = (scale_factor, scale_factor, scale_factor)
        print(f"[pilot] Applied uniform scale {scale_factor:.4f} "
              f"to fit {TARGET_CHARACTER_HEIGHT}m height")

    # Translate so the mesh's feet (lowest Z) sit at world Z=0. Take the
    # original min_z * scale_factor; that's the post-scale floor offset
    # that we need to nullify.
    feet_offset_z = min_z * (TARGET_CHARACTER_HEIGHT / tallest_axis if tallest_axis > 0 else 1.0)
    wrapper.location = (
        -(min_x + width / 2) * (TARGET_CHARACTER_HEIGHT / tallest_axis if tallest_axis > 0 else 1.0),
        -(min_y + depth / 2) * (TARGET_CHARACTER_HEIGHT / tallest_axis if tallest_axis > 0 else 1.0),
        -feet_offset_z,
    )

    # Force a scene update so the new transforms propagate before render
    bpy.context.view_layer.update()

    return wrapper


# (Legacy import_weapon + verify_animation_loaded removed when pilot
# pivoted from the SDXL stylization path to direct .glb rendering — see
# PILOT_RESULTS.md for the full reasoning.)


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


def render_all_directions(character_wrapper: bpy.types.Object) -> None:
    """Outer loop: rotate the character wrapper for each of 8 facings,
    render an RGBA PNG. Wrapper rotation is around world Z (yaw)."""
    scene = bpy.context.scene
    raw_dir = OUTPUT_ROOT / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)

    for dir_name, yaw_deg in DIRECTIONS:
        character_wrapper.rotation_euler = (0, 0, math.radians(yaw_deg))
        for f_idx in range(FRAMES_PER_DIRECTION):
            scene.frame_set(1)  # static pose for now; armature anim later
            out_path = raw_dir / f"{dir_name}_{f_idx:02d}.png"
            scene.render.filepath = str(out_path)
            bpy.ops.render.render(write_still=True)
            print(f"  [{dir_name}] → {out_path.name}")


# ── Entrypoint ──────────────────────────────────────────────────────────────


def main() -> None:
    print(f"[pilot] Project root: {PROJECT_ROOT}")
    print(f"[pilot] Character: {CHARACTER_GLB}")
    print(f"[pilot] Output: {OUTPUT_ROOT}")

    if not CHARACTER_GLB.exists():
        print(f"[pilot] ERROR: missing character glb {CHARACTER_GLB}")
        sys.exit(1)

    clear_scene()
    wrapper = import_character()
    setup_camera()
    setup_lighting()
    setup_render_settings()
    render_all_directions(wrapper)

    print(f"[pilot] Done. Rendered {len(DIRECTIONS) * FRAMES_PER_DIRECTION} frames.")
    print(f"[pilot] Output dir: {OUTPUT_ROOT / 'raw'}")


if __name__ == "__main__":
    main()
