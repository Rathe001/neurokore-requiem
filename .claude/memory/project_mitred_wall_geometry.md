---
name: mitred-wall-geometry
description: "Procedural room walls use 45° mitred corners — trapezoidal walls tiling at the diagonal, no overlap, no exposed mitre face"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

`WallBuilder.build_room_mesh` builds each wall as a TRAPEZOIDAL footprint
(outer edge longer than inner edge by `2*wall_thickness`). Two perpendicular
walls share the same diagonal seam at each corner — they tile flush.

**Why:** Old geometry overshot each wall by `wall_thickness/2` past the
nominal corner so corners were filled with a 0.4×0.4 cube. Debug-block
visualization made these cubes visible as separate boxes; user wanted a
clean 45° mitre instead. Mitring eliminates the overshoot — each wall
ends exactly at the corner.

**How to apply:** No corner-mitre face is rendered. The seam where two
trapezoidal walls meet is hidden inside their material (no camera angle
can see into the empty wedge between them). Adding a mitre face is
unnecessary and the desired-normal direction is ambiguous for square
rooms (perpendicular to the diagonal can be NE or SW — neither
"outward from room" in a useful sense). If you ever need to fill the
mitre seam (e.g. for shadow-volume correctness), use `_add_oriented_vquad`
with `(b - a).cross(Vector3.UP)` as the reference for one of the two
choices, not `(corner_o - center)` which lies in the face plane.

Related: [[corridor-room-jamb-alignment]] for the corridor-side mitre
fixes (corridor walls still overlap into room walls — separate concern).
