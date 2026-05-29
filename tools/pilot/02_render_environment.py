"""Phase 0 graybox environment renderer for the facility corridor zone.

Produces minimal procedural geometry — no Meshy/MJ assets yet — at the
same iso camera + lighting as the character pipeline. Output feeds the
depth-sort validation scene in godot_test/.

Pieces:
- floor_tile.png    2m x 2m flat concrete (tileable)
- wall_section.png  2m wide x 2.5m tall vertical wall, centered on the
                    SOUTH edge of a floor tile (X axis), facing +Y.
                    For "west wall" we'll rotate this 90° at runtime
                    or re-render as a separate piece in Phase 1.

Output:
    tools/pilot/output/environment/facility/{floor_tile,wall_section}.png

Run:
    blender -b -P tools/pilot/02_render_environment.py
"""
import math
import sys
from pathlib import Path

import bpy  # type: ignore

PILOT_ROOT = Path(__file__).parent
OUTPUT_ROOT = PILOT_ROOT / "output" / "environment" / "facility"

# Resolution: 512 because tile/wall pixels will be repeated and zoomed
# in the game viewport — clarity matters more than for one-off characters.
RESOLUTION = 512

# Iso angle matches the character renderer so lighting/perspective
# integrate cleanly when characters walk through these tiles.
CAMERA_PITCH_DEG = 30.0
CAMERA_YAW_DEG = 45.0
CAMERA_DISTANCE = 10.0
# Tight enough to fill the frame with a 2m x 2.5m piece + ~15% margin.
CAMERA_ORTHO_SCALE = 3.5


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


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
        CAMERA_DISTANCE * math.sin(pitch_rad),
    )

    # Aim at world origin (Z=0) — for environment pieces, the ground
    # plane IS the focal plane. Character renderer offsets +1m up to
    # aim at chest height.
    track_target = bpy.data.objects.new("CamTarget", None)
    track_target.location = (0, 0, 0)
    bpy.context.scene.collection.objects.link(track_target)
    track = cam.constraints.new(type="TRACK_TO")
    track.target = track_target
    track.track_axis = "TRACK_NEGATIVE_Z"
    track.up_axis = "UP_Y"

    bpy.context.scene.camera = cam
    return cam


def setup_lighting() -> None:
    """Same 3-point setup as the character renderer so tones match
    when a character walks in front of one of these walls."""
    def add_light(name, kind, energy, color, location):
        ld = bpy.data.lights.new(name=name, type=kind)
        ld.energy = energy
        ld.color = color
        light = bpy.data.objects.new(name, ld)
        light.location = location
        bpy.context.scene.collection.objects.link(light)

    add_light("KeyLight",  "AREA", 600.0, (1.0, 0.85, 0.7),  (5, -5, 6))
    add_light("FillLight", "AREA", 120.0, (0.6, 0.75, 1.0), (-3, -3, 4))
    add_light("RimLight",  "AREA", 300.0, (0.4, 0.85, 1.0), (-2,  4, 3))


def setup_render() -> None:
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
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"


def make_concrete_material(name: str, base_color: tuple[float, float, float]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*base_color, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    return mat


def build_floor_tile() -> bpy.types.Object:
    """2m x 2m plane centered at world origin, sitting on Z=0."""
    bpy.ops.mesh.primitive_plane_add(size=2.0, location=(0, 0, 0))
    plane = bpy.context.active_object
    plane.name = "FloorTile"
    plane.data.materials.append(make_concrete_material("FloorMat", (0.50, 0.50, 0.53)))
    return plane


def build_wall_section() -> bpy.types.Object:
    """Vertical wall: 2m wide (X), 0.1m thick (Y), 2.5m tall (Z).
    Wall foot-center sits at WORLD ORIGIN so the rendered image has
    its pivot point (foot-center) at pixel-center. In Godot, this
    means a Sprite2D at world_to_screen(wall_foot_world_pos) with
    centered=true lines up perfectly with the floor."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 1.25))
    wall = bpy.context.active_object
    wall.name = "WallSection"
    wall.scale = (2.0, 0.1, 2.5)
    bpy.ops.object.transform_apply(scale=True)
    wall.data.materials.append(make_concrete_material("WallMat", (0.58, 0.58, 0.60)))
    return wall


def render_to(filename: str) -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    out_path = OUTPUT_ROOT / filename
    bpy.context.scene.render.filepath = str(out_path)
    bpy.ops.render.render(write_still=True)
    print(f"[env] wrote {out_path}")


def build_each(piece_name: str, builder) -> None:
    clear_scene()
    setup_camera()
    setup_lighting()
    setup_render()
    builder()
    render_to(f"{piece_name}.png")


def main() -> None:
    build_each("floor_tile",   build_floor_tile)
    build_each("wall_section", build_wall_section)
    print(f"[env] done — output dir: {OUTPUT_ROOT}")


if __name__ == "__main__":
    main()
