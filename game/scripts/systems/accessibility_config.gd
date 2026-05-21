class_name AccessibilityConfig
extends Resource

## Disables motion-driven camera effects (sprint chromatic aberration,
## future motion blur, etc.). Players prone to motion sickness can flip
## this off in settings to remove screen distortion on movement.
@export var reduce_camera_effects: bool = false

## Disables blood spawns entirely — decals on floor/walls/characters,
## particle mist, and bloody footprints. Hit-flash + damage numbers
## still play so combat feedback isn't lost. Standard content setting
## for players who'd rather not have the gore on screen.
@export var disable_blood: bool = false
