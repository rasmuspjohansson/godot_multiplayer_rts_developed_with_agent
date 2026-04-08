extends CharacterBody2D

signal unit_died(peer_id: int)

@export var owner_peer_id: int = 0
@export var owner_name: String = ""

var army_id: String = ""
var speed: float = 200.0 / 6.0
var hp: float = 100.0
var attack: float = 10.0
var defense: float = 2.0
var attack_range: float = 50.0

var move_target: Vector2 = Vector2.ZERO
var is_moving := false
var is_dead := false
var attack_timer: float = 0.0
var _selected := false
# Client: interpolate toward server position for smooth movement
var sync_target_position: Vector2 = Vector2.ZERO
var sync_target_hp: float = 100.0

# Server: bounds check (must match World.gd map size)
const MAP_WIDTH := 1280
const MAP_HEIGHT := 720
const MAP_MARGIN := 200
var _logged_position_invalid := false

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
			var idx = 0
			if owner_peer_id in GameState.players:
				idx = clampi(GameState.players[owner_peer_id].get("color_index", 0), 0, GameState.PLAYER_COLORS.size() - 1)
			sprite.color = GameState.PLAYER_COLORS[idx]

func _physics_process(delta):
	if is_dead:
		return
	if multiplayer.is_server():
		_server_process(delta)
	else:
		# Client: velocity toward sync target + move_and_slide() so physics resolves collisions
		if sync_target_position != Vector2.ZERO:
			var dist = global_position.distance_to(sync_target_position)
			if dist > 1.0:
				velocity = (sync_target_position - global_position).normalized() * speed
			else:
				velocity = Vector2.ZERO
			move_and_slide()
			hp = lerpf(hp, sync_target_hp, clampf(delta * 8.0, 0.0, 1.0))
		else:
			velocity = Vector2.ZERO
			move_and_slide()
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

	if global_position.x < -MAP_MARGIN or global_position.x > MAP_WIDTH + MAP_MARGIN or global_position.y < -MAP_MARGIN or global_position.y > MAP_HEIGHT + MAP_MARGIN:
		if not _logged_position_invalid:
			_logged_position_invalid = true
			print("TEST_SERVER_UNIT_POSITION_INVALID: %s out_of_bounds" % name)

	attack_timer -= delta
	if attack_timer <= 0:
		_try_attack()

func _try_attack():
	var world = get_parent()
	if world == null:
		return
	var candidates: Array
	if world.has_method("get_units_in_radius"):
		candidates = world.get_units_in_radius(global_position, attack_range)
	else:
		candidates = []
		for child in world.get_children():
			if child is CharacterBody2D:
				candidates.append(child)
	for child in candidates:
		if child == self or not child is CharacterBody2D:
			continue
		if child.is_dead:
			continue
		if child.owner_peer_id == owner_peer_id:
			continue
		var dist = global_position.distance_to(child.global_position)
		if dist <= attack_range:
			var dmg = max(1, attack - child.defense)
			GameState.last_combat_time = Time.get_ticks_msec() / 1000.0
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
