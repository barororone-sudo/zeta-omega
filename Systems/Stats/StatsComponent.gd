@tool
extends Node
class_name StatsComponent

# --- SIGNALS ---
signal health_changed(new_value: float, max_value: float)
signal xp_changed(new_value: int, max_value: int)
signal leveled_up(new_level: int)
signal died()

# --- EXPORTED STATS ---
@export_group("Vitality")
@export var max_health: float = 100.0:
	set(value):
		max_health = value
		# Update current health if MAX changes ? Optionally clamp
		if current_health > max_health: current_health = max_health
		
@export var current_health: float = 100.0:
	set(value):
		current_health = clamp(value, 0.0, max_health)
		health_changed.emit(current_health, max_health)
		if current_health <= 0:
			died.emit()

@export var defense: float = 0.0

@export_group("Power")
@export var attack_power: float = 10.0

@export_group("Progression")
@export var level: int = 1
@export var current_xp: int = 0:
	set(value):
		current_xp = value
		xp_changed.emit(current_xp, xp_to_next_level)
		_check_level_up()

@export var xp_to_next_level: int = 100

# --- LIFECYCLE ---
func _ready():
	# Initial sync
	health_changed.emit(current_health, max_health)
	xp_changed.emit(current_xp, xp_to_next_level)

# --- PUBLIC API ---

# 1. DAMAGE LOGIC
func take_damage(amount: float):
	if current_health <= 0: return # Already dead
	
	# Calculate mitigation
	var damage_taken = max(amount - defense, 1.0) # Always take at least 1 damage
	
	current_health -= damage_taken
	
	print("⚔️ [", get_parent().name, "] Dégâts reçus : ", damage_taken, " (Brut: ", amount, " - Def: ", defense, "). Vie restante : ", current_health, "/", max_health)

# 2. HEALING LOGIC
func heal(amount: float):
	if current_health <= 0: return # Cannot heal dead? Or maybe yes? Let's say no for now.
	
	var amount_healed = min(amount, max_health - current_health)
	current_health += amount
	
	print("💖 [", get_parent().name, "] Soigné de : ", amount_healed, ". Vie : ", current_health, "/", max_health)

# 3. XP LOGIC
func add_xp(amount: int):
	print("✨ [", get_parent().name, "] +", amount, " XP !")
	current_xp += amount

func _check_level_up():
	while current_xp >= xp_to_next_level:
		current_xp -= xp_to_next_level
		level_up()
		# Repeat in case of massive XP gain

func level_up():
	level += 1
	var old_max_hp = max_health
	var old_atk = attack_power
	
	# Exponential / Percentage Growth
	max_health *= 1.10 # +10% HP
	attack_power *= 1.05 # +5% Attack
	
	# Full Heal on Level Up
	current_health = max_health
	
	# Curve: XP needed increases by 20%
	xp_to_next_level = int(float(xp_to_next_level) * 1.2)
	
	print("🆙 [", get_parent().name, "] NIVEAU UP ! ", level - 1, " -> ", level)
	print("   - Max HP : ", old_max_hp, " -> ", max_health)
	print("   - ATK : ", old_atk, " -> ", attack_power)
	
	leveled_up.emit(level)
	health_changed.emit(current_health, max_health)
	xp_changed.emit(current_xp, xp_to_next_level)
