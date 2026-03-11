extends CharacterBody2D

signal unit_died(peer_id: int)

@export var owner_peer_id: int = 0
@export var owner_name: String = ""

var speed: float = 200.0
var hp: float = 100.0
var attack: float = 10.0
var defense: float = 2.0
var attack_range: float = 50.0

var move_target: Vector2 = Vector2.ZERO
var is_moving := false
var is_dead := false
var attack_timer: float = 0.0
var selected := false

@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sprite: ColorRect = $ColorRect
@onready var hp_label: Label = $HPLabel

func _ready():
	nav_agent.path_desired_distance = 4.0
	nav_agent.target_desired_distance = 4.0
	_update_visuals()

func _update_visuals():
	if hp_label:
		hp_label.text = "%s\nHP:%d" % [owner_name, int(hp)]
	if sprite and selected:
		sprite.color = Color.YELLOW
	elif sprite:
		sprite.color = Color.GREEN_YELLOW if not is_dead else Color.DARK_RED

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
			var direction = (next_pos - global_position).normalized()
			velocity = direction * speed
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
		var dist = global_position.distance_to(child.global_position)
		if dist <= attack_range:
			var dmg = max(1, attack - child.defense)
			print("TEST_010_COMBAT: %s attacking %s (dist=%.1f, dmg=%.1f)" % [owner_name, child.owner_name, dist, dmg])
			child.take_damage(dmg, owner_peer_id)
			attack_timer = 1.0
			return

func take_damage(dmg: float, attacker_id: int):
	if is_dead:
		return
	hp -= dmg
	print("Combat: %s took %.1f damage, HP=%.1f" % [owner_name, dmg, hp])
	rpc("_sync_hp", hp)
	if hp <= 0:
		is_dead = true
		print("Combat: %s has been defeated!" % owner_name)
		rpc("_sync_death")
		unit_died.emit(owner_peer_id)

@rpc("authority", "call_local", "reliable")
func _sync_hp(new_hp: float):
	hp = new_hp
	_update_visuals()

@rpc("authority", "call_local", "reliable")
func _sync_death():
	is_dead = true
	hp = 0
	if sprite:
		sprite.color = Color.DARK_RED
	_update_visuals()

@rpc("any_peer", "reliable")
func request_move(target: Vector2):
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender != owner_peer_id:
		return
	var move_marker = "TEST_009_MOVE" if owner_name == "A" else "TEST_009_MOVE_B"
	print("%s: Server accepted move for %s to (%d,%d)" % [move_marker, owner_name, int(target.x), int(target.y)])
	_do_move(target)
	rpc("_sync_move_target", target)

func _do_move(target: Vector2):
	move_target = target
	is_moving = true
	if nav_agent:
		nav_agent.target_position = target

@rpc("authority", "reliable")
func _sync_move_target(target: Vector2):
	move_target = target
	is_moving = true
	if nav_agent:
		nav_agent.target_position = target

@rpc("authority", "call_local", "reliable")
func _sync_position(pos: Vector2):
	global_position = pos

func select():
	selected = true
	_update_visuals()
	var marker = "TEST_008_SELECT" if owner_name == "A" else "TEST_008_SELECT_B"
	print("%s: Unit '%s' selected" % [marker, owner_name])

func deselect():
	selected = false
	_update_visuals()
