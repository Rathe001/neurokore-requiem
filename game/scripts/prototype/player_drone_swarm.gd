class_name PlayerDroneSwarm
extends Node

## Automaton Drone Swarm — N hover drones spawned from the
## `automaton_drones` perk aggregate. Drones parent to the world root so
## they keep world-space transforms (their CharacterBody3D move_and_slide
## owns the position). reconcile() runs on perks_changed and death/respawn
## to add or remove drones; clamps against AUTOMATON_MAX_DRONES.

const DRONE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_drone.tscn")
const AUTOMATON_MAX_DRONES := 8

var _host: PrototypePlayer
var _drones: Array[PrototypeDrone] = []


func setup(host: PrototypePlayer) -> void:
	_host = host


func get_drone_count() -> int:
	return _drones.size()


func reconcile() -> void:
	var live: Array[PrototypeDrone] = []
	for d in _drones:
		if d != null and is_instance_valid(d):
			live.append(d)
	_drones = live
	var target := 0
	if _host.is_alive():
		target = mini(int(round(Effects.get_aggregate(&"automaton_drones"))), AUTOMATON_MAX_DRONES)
	while _drones.size() > target:
		var d: PrototypeDrone = _drones.pop_back()
		if d != null and is_instance_valid(d):
			d.queue_free()
	var parent := _host.get_parent()
	while _drones.size() < target and parent != null:
		var d := DRONE_SCENE.instantiate() as PrototypeDrone
		if d == null:
			break
		parent.add_child(d)
		d.global_position = _host.global_position + Vector3(0.0, 1.6, 0.0)
		d.setup(_host)
		_drones.append(d)


func cleanup() -> void:
	for d in _drones:
		if d != null and is_instance_valid(d):
			d.queue_free()
	_drones.clear()
