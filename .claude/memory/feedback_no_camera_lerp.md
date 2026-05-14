---
name: No camera lerp smoothing
description: Fixed isometric camera should snap to player, not lerp — lerp causes dizzying float effect
type: feedback
---

Camera follow in the fixed isometric view must snap to player position, not use lerp/smoothing. The slight delay from interpolation creates a dizzying, floaty effect that the user noticed immediately.

**Why:** The fixed camera angle means any lag between player movement and camera follow is perceptible and uncomfortable. Unlike third-person cameras where smoothing hides jitter, isometric cameras need rigid 1:1 tracking.

**How to apply:** Never add interpolation/smoothing to the isometric follow camera. If camera effects are needed later (screen shake, zoom transitions), implement them as temporary offsets on top of the snap position.
