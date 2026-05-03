class_name TalentTree extends Resource

## A class's talent tree — the flat list of TalentNode entries that fill
## the 8×3 grid for one stat. Sparse is fine: empty slots just don't
## resolve to a node when the panel queries by (tier, node_idx).
##
## Convention: live at `res://resources/talents/{stat_id}.tres` and
## TalentState auto-loads them by stat ID on _ready. Adding a new node
## is a .tres edit in the editor — append to nodes[] and set its
## (tier, node_idx).

@export var nodes: Array[TalentNode] = []
