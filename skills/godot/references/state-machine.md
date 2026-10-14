# Godot — máquina de estados (FSM) e input desacoplado

> Patrón para modelar comportamiento de actores (jugador, enemigos, jefes) sin un `_process` lleno de booleanos que se pisan. Es la decisión de arquitectura más común en gameplay de Godot.

## El problema que resuelve

Sin FSM, cada comportamiento nuevo añade un bool y una rama al `_process`, y las combinaciones explotan:

```gdscript
# ANTI-PATRÓN
func _process(delta: float) -> void:
    if is_dead: ...
    if is_attacking: ...
    elif is_dashing: ...
    elif is_attacking and is_dashing: ...   # combinaciones infinitas, bugs asegurados
```

Una FSM lo reemplaza por tres reglas: **un solo estado activo**, cada estado en **su propio script** y transiciones **explícitas**.

## Las cuatro piezas

| Pieza | Rol |
|-------|-----|
| **State** (base) | Contrato: métodos vacíos que cada estado llena |
| **StateMachine** | Nodo que inyecta referencias, guarda el estado actual y delega |
| **Estados** | Hijos de la máquina: `Idle`, `Run`, `Attack`… |
| **Actor** | El dueño (`CharacterBody2D`); los estados lo mueven vía `actor` |

Estructura típica:

```text
Player (CharacterBody2D)          # Actor
├── Sprite2D
├── InputController               # única fuente de entrada (ver abajo)
└── StateMachine
    ├── Idle    (State)
    ├── Run     (State)
    ├── Jump    (State)
    └── Attack  (State)
```

Los estados son **hijos** de la máquina; la máquina los recoge con `get_children()`. Añadir un estado = añadir un nodo, sin tocar la máquina.

## Clase base `State`

```gdscript
class_name State
extends Node

var state_machine: StateMachine
var actor: CharacterBody2D

func enter() -> void: pass
func exit() -> void: pass
func process(_delta: float) -> void: pass
func physics_process(_delta: float) -> void: pass

func change_to(state_name: StringName) -> void:
    state_machine.change_to(state_name)
```

Dos puntos clave que casi todos incumplen:

- **Los estados no usan `_process`/`_physics_process`.** Usan métodos propios `process()`/`physics_process()` que la máquina llama **solo para el estado activo**. Si un estado declarara `_process`, correría siempre, incluso inactivo.
- **El setup va en `enter()`, nunca en `_ready()`.** Godot ejecuta el `_ready()` de los hijos **antes** que el del padre: cuando `Idle._ready()` corre, la máquina aún no inyectó `actor` ni `state_machine` → referencia nula.

## La `StateMachine`

```gdscript
class_name StateMachine
extends Node

@export var initial_state: State
var current_state: State

func _ready() -> void:
    for child in get_children():
        if child is State:
            child.state_machine = self
            child.actor = owner          # el Actor que contiene la máquina

    if initial_state == null:
        initial_state = get_child(0) as State
    change_to(initial_state.name)

func _process(delta: float) -> void:
    if current_state:
        current_state.process(delta)

func _physics_process(delta: float) -> void:
    if current_state:
        current_state.physics_process(delta)

func change_to(state_name: StringName) -> void:
    var next := get_node_or_null(state_name) as State
    if next == null or next == current_state:
        return                            # guard: evita recambios redundantes
    if current_state:
        current_state.exit()
    current_state = next
    current_state.enter()
```

`change_to` recibe un **nombre** porque los estados son hermanos y no se conocen entre sí. La máquina usa `owner`; si la máquina está anidada, ajustar a la referencia correcta del Actor.

## Abstracción de la entrada (`InputController`)

> **Regla de oro: solo un nodo lee `Input.*`. Todo lo demás consume lo que ese nodo expone.**

Así el jugador no sabe si hay teclado, gamepad o joystick táctil; cambiar de plataforma no toca los estados.

```gdscript
class_name InputController
extends Node

signal attack_pressed
signal cast_requested(element: int)

@export var use_touch_input: bool = false

var move_vector: Vector2 = Vector2.ZERO
var defending: bool = false

func _process(_delta: float) -> void:
    if use_touch_input:
        move_vector = _get_touch_vector()          # Android: joystick táctil
    else:
        move_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
    defending = Input.is_action_pressed("defend")
    if Input.is_action_just_pressed("attack"):
        attack_pressed.emit()
```

- **Input Map**: una acción por dirección con **varias teclas** (A + ←, etc.). `Input.get_vector()` resuelve diagonales **normalizadas** (misma velocidad en diagonal) y funciona con WASD y flechas sin código extra.
- Si mañana añades una tecla o una plataforma de entrada, se toca **solo el `InputController`**; ningún personaje.

```gdscript
class_name PlayerIdle
extends State

func enter() -> void:
    actor.play_animation("idle")

func process(_delta: float) -> void:
    if actor.input_controller.move_vector != Vector2.ZERO:
        change_to(&"Run")
```

```gdscript
class_name PlayerRun
extends State

func enter() -> void:
    actor.play_animation("run")

func physics_process(_delta: float) -> void:
    var dir: Vector2 = actor.input_controller.move_vector
    actor.velocity = dir * actor.move_speed
    actor.move_and_slide()                          # siempre en physics_process
    if dir == Vector2.ZERO:
        change_to("Idle")
```

## La misma máquina para todo

Player, enemigos y jefes comparten `state_machine.gd`; solo cambian los estados hijos. Reutilización pura.

```gdscript
class_name EnemyChase
extends State

func physics_process(_delta: float) -> void:
    if actor.player_in_attack_range():
        change_to("Attack")
        return
    var dir := actor.global_position.direction_to(actor.player.global_position)
    actor.velocity = dir * actor.speed
    actor.move_and_slide()
    if not actor.player_in_aggro_range():
        change_to("Patrol")
```

**Jefes = misma máquina + fases por HP.** El jefe interrumpe lo que esté haciendo al cambiar de fase:

```gdscript
class_name Boss
extends CharacterBody2D

enum Phase { ONE, TWO, THREE }
var current_phase: Phase = Phase.ONE

func take_damage(amount: float) -> void:
    hp -= amount
    match current_phase:
        Phase.ONE:
            if hp < MAX_HP * 0.7: _enter_phase(Phase.TWO)
        Phase.TWO:
            if hp < MAX_HP * 0.3: _enter_phase(Phase.THREE)

func _enter_phase(new_phase: Phase) -> void:
    current_phase = new_phase
    $StateMachine.change_to("Enrage")
```

## Avanzado

- **Varias máquinas en paralelo**: solo cuando dos comportamientos pueden ocurrir a la vez (moverse **y** defender). Si son excluyentes, una sola máquina.
- **Estados parametrizados** en lugar de duplicar: un único `AttackState` con `@export` para animación/daño, y varias instancias con distinto valor en el inspector.

```gdscript
class_name AttackState
extends State

@export var animation: StringName = &"attack"
@export var damage: float = 10.0

func enter() -> void:
    actor.play_animation(animation)
    actor.attack_hitbox.monitoring = true
    actor.anim.animation_finished.connect(_on_finished, CONNECT_ONE_SHOT)

func exit() -> void:
    actor.attack_hitbox.monitoring = false

func _on_finished(_anim: StringName) -> void:
    change_to("Idle")
```

- **Transiciones centralizadas vs descentralizadas**: descentralizada = cada estado decide cuándo irse (más legible). Centralizada = el estado expone `get_transition()` y la máquina lo consulta (mejor cuando muchas reglas compiten, p. ej. el jefe que interrumpe para entrar en fase). Se pueden mezclar.

## Trampas (leer antes de escribir)

1. **Cambiar de estado dentro de `enter()`**: riesgo de recursión infinita entre estados. No transicionar en `enter()`.
2. **Configurar un estado en `_ready()`**: los hijos corren antes que el padre; `actor` todavía es nulo. Todo va en `enter()`.
3. **Llamar `change_to()` dos veces en el mismo frame**: el guard `if next == current_state: return` lo evita.
4. **Física en `process()`**: el movimiento va en `physics_process()`.
5. **Estados que leen `Input` directo**: rompen la abstracción; solo el `InputController` toca `Input.*`.
6. **Estado gigante**: si supera ~100 líneas, probablemente son 2-3 estados (`Attack` → `Attack` + `Recover`).
7. **Rutas a hermanos hardcodeadas** (`get_parent().get_node("Run")`): centralizar en `change_to(nombre)`.
8. **Comparar estados por identidad de nodo**: los nodos se reordenan al editar la escena; usar nombres.
9. **Olvidar el `exit()`**: hitboxes, invulnerabilidad y velocidades activadas en `enter()` deben desactivarse en `exit()`, o quedan efectos fantasma.

## Resumen

- Un solo estado activo; la máquina delega, los estados se aíslan.
- `enter()` para montar, `exit()` para limpiar.
- El estado activo decide irse con `change_to("Nombre")`.
- Nadie toca `Input` salvo el `InputController` → teclado/gamepad/táctil intercambiables.
- La misma máquina sirve para Player, enemigos y jefes; cambian los estados, no el motor.

## Recursos

- Movimiento 2D: `https://docs.godotengine.org/en/stable/tutorials/2d/2d_movement.html`
- Input / InputMap: `https://docs.godotengine.org/en/stable/tutorials/inputs/input_examples.html`
- GDQuest — patrón State: `https://www.gdquest.com/tutorial/godot/design-patterns/state/`
