extends CharacterBody2D

signal unit_died(peer_id: int)

@export var owner_peer_id: int = 0
@export var owner_name: String = ""

var army_id: String = ""
var speed: float = 200.0
var hp: float = 100.0
var attack: float = 10.0
var defense: float = 2.0
var attack_range: float = 50.0

var move_target: Vector2 = Vector2.ZERO
var is_moving := false
var is_dead := false
var attack_timer: float = 0.0
var _selected := false

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: ColorRect = $ColorRect

func _ready():
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = 4.0
	_update_visuals()

func set_move_target(target: Vector2):
	move_target = target
	is_moving = true
	if nav_agent:
		nav_agent.target_position = target

func set_selected(val: bool):
	_selected = val
	_update_visuals()

func _update_visuals():
	if sprite:
		if is_dead:
			sprite.color = Color.DARK_RED
		elif _selected:
			sprite.color = Color.YELLOW
		else:
			sprite.color = Color.GREEN_YELLOW

func _physics_process(delta):
	if is_dead:
		return
	if multiplayer.is_server():
		_server_process(delta)
	_update_visuals()

func _server_process(delta):
	if is_moving and nav_agent:
		if nav_agent.is_navigation_finished():
			is_moving = false
			velocity = Vector2.ZERO
		else:
			var next_pos = nav_agent.get_next_path_position()
			var dir = (next_pos - global_position).normalized()
			velocity = dir * speed
			move_and_slide()

	attack_timer -= delta
	if attack_timer <= 0:
		_try_attack()

func _try_attack():
	var world = get_parent()
	if world == null:
		return
	for child in world.get_children():
		if child == self or not child is CharacterBody2D:
			continue
		if child.is_dead:
			continue
		if child.owner_peer_id == owner_peer_id:
			continue
		var dist = global_position.distance_to(child.global_position)
		if dist <= attack_range:
			var dmg = max(1, attack - child.defense)
			print("TEST_010_COMBAT: %s(%s) attacking %s(%s) dist=%.1f dmg=%.1f" % [owner_name, army_id, child.owner_name, child.army_id, dist, dmg])
			child.take_damage(dmg, owner_peer_id)
			attack_timer = 1.0
			return

func take_damage(dmg: float, _attacker_id: int):
	if is_dead:
		return
	hp -= dmg
	if hp <= 0:
		is_dead = true
		print("Combat: soldier '%s' in %s died" % [name, army_id])
		unit_died.emit(owner_peer_id)
		if sprite:
			sprite.color = Color.DARK_RED
		var world = get_parent()
		if world and world.has_method("_notify_unit_death"):
			world._notify_unit_death(name)
		print("TEST_UNIT_CLEANUP: unit %s queued for removal" % name)
		get_tree().create_timer(0.5).timeout.connect(func(): queue_free())
