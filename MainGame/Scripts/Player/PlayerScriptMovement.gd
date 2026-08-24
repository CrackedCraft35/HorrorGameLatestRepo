extends CharacterBody3D

# ==========================================
# PARÁMETROS EDITABLES EN EL INSPECTOR
# ==========================================

@export_category("Movimiento")
@export var walk_speed: float = 2.5
@export var sprint_speed: float = 5.0
@export var acceleration: float = 8.0
@export var friction: float = 10.0
@export var gravity: float = 9.8

@export_category("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_drain: float = 20.0
@export var stamina_regen: float = 15.0
@export var min_stamina_to_sprint: float = 15.0

@export_category("Cámara - Headbob (Caminar / Correr)")
# Valores balanceados (no bruscos)
@export var bob_freq_walk: float = 4.5
@export var bob_amp_walk: float = 0.025
@export var bob_freq_sprint: float = 7.5
@export var bob_amp_sprint: float = 0.05
@export var bob_transition_speed: float = 6.0

@export_category("Cámara - Tilt (Inclinación Lateral)")
@export var tilt_angle: float = 0.035
@export var tilt_speed: float = 6.0

@export_category("Control de Ratón")
# Ajustado a la mitad exacta (x5)
@export var mouse_sensitivity: float = 0.008

# ==========================================
# REFERENCIAS Y VARIABLES INTERNAS
# ==========================================

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var current_stamina: float
var can_sprint: bool = true
var is_sprinting: bool = false

var t_bob: float = 0.0
var current_bob_amp: float = 0.0
var current_bob_freq: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	current_stamina = max_stamina

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		head.rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-85), deg_to_rad(85))
		
	if Input.is_physical_key_pressed(KEY_ESCAPE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	# 1. Gravedad
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2. Lectura directa de teclado (WASD)
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
	input_dir = input_dir.normalized()

	# 3. Lógica de Sprint y Stamina
	var is_moving = input_dir != Vector2.ZERO
	var wants_to_sprint = Input.is_physical_key_pressed(KEY_SHIFT) and input_dir.y < 0
	
	if wants_to_sprint and can_sprint and is_moving:
		is_sprinting = true
		current_stamina -= stamina_drain * delta
		if current_stamina <= 0:
			current_stamina = 0
			can_sprint = false
			is_sprinting = false
	else:
		is_sprinting = false
		current_stamina += stamina_regen * delta
		if current_stamina > max_stamina:
			current_stamina = max_stamina
		if current_stamina >= min_stamina_to_sprint:
			can_sprint = true

	# 4. Movimiento
	var current_speed = sprint_speed if is_sprinting else walk_speed
	var direction = (head.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if is_on_floor():
		if direction:
			velocity.x = lerp(velocity.x, direction.x * current_speed, acceleration * delta)
			velocity.z = lerp(velocity.z, direction.z * current_speed, acceleration * delta)
		else:
			velocity.x = lerp(velocity.x, 0.0, friction * delta)
			velocity.z = lerp(velocity.z, 0.0, friction * delta)

	move_and_slide()

	# 5. Efectos de Cámara
	_handle_camera_effects(delta, is_moving, input_dir.x)

func _handle_camera_effects(delta: float, is_moving: bool, input_x: float) -> void:
	var target_freq: float = 0.0
	var target_amp: float = 0.0
	
	# Solo genera bamboleo si te estás desplazando activamente en el suelo
	if is_moving and is_on_floor() and velocity.length() > 0.5:
		if is_sprinting:
			target_freq = bob_freq_sprint
			target_amp = bob_amp_sprint
		else:
			target_freq = bob_freq_walk
			target_amp = bob_amp_walk

	current_bob_freq = lerp(current_bob_freq, target_freq, bob_transition_speed * delta)
	current_bob_amp = lerp(current_bob_amp, target_amp, bob_transition_speed * delta)

	t_bob += current_bob_freq * delta

	# Calculamos la posición offset local de la cámara partiendo de (0,0,0)
	var target_pos = Vector3.ZERO
	if current_bob_amp > 0.001:
		target_pos.y = sin(t_bob * PI * 2.0) * current_bob_amp
		target_pos.x = cos(t_bob * PI) * (current_bob_amp * 0.5)

	# Se aplica a la Camera3D directamente
	camera.position = camera.position.lerp(target_pos, bob_transition_speed * delta)

	# Inclinación lateral (Tilt)
	var target_tilt = 0.0
	if is_moving and is_on_floor():
		target_tilt = -input_x * tilt_angle
	
	camera.rotation.z = lerp_angle(camera.rotation.z, target_tilt, tilt_speed * delta)
