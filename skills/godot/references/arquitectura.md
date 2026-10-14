# Godot — arquitectura de escenas y desacoplamiento

> Cómo estructurar un proyecto Godot para que escale: composición, señales, autoloads y datos en `Resource`.

## Composición de escenas

- Una escena = un **componente** con una responsabilidad. Se instancia donde se necesita.
- Preferir **nodos hijos como componentes** (vida, daño, movimiento, input) antes que heredar de una clase base que acumula lógica.
- Usar `%NombreÚnico` (Unique Name in Owner, `%Nombre`) para referenciar nodos internos de una escena sin rutas frágiles:

```gdscript
@onready var label: Label = %ScoreLabel
```

- Definir **señales en el componente** y dejar que el contenedor las conecte. El hijo no conoce a los hermanos.

## Señales

```gdscript
# El componente declara y emite
signal pressed(value: int)

func _on_button_pressed() -> void:
    pressed.emit(42)

# El contenedor escucha
func _ready() -> void:
    %MyButton.pressed.connect(_on_pressed)

func _on_button_pressed(value: int) -> void:
    print("recibí ", value)
```

- Conectar en el **editor** cuando la relación es fija; en código cuando es dinámica.
- `await mi_senal` para esperar de forma secuencial sin callbacks anidados.
- Un **event bus** como autoload puede desacoplar sistemas que no comparten ancestro (`EventBus.enemy_died.emit(enemy)`), pero es fácil abusar: usarlo solo cuando no hay un padre común razonable.

## Autoloads (singletons)

- Solo para estado **realmente global**: `GameState`, `AudioManager`, `SaveManager`, un `EventBus`.
- Se registran en `Project Settings → Autoload`.
- No meter lógica de gameplay en un autoload: se vuelve un "dios" global imposible de reutilizar y testear.
- Alternativa: **inyección por escena** (el contenedor pasa la dependencia) cuando el alcance no es global.

## Datos con `Resource`

```gdscript
class_name EnemyData
extends Resource

@export var display_name: String
@export var max_health: int = 100
@export var speed: float = 80.0
```

- `.tres` se editan en el inspector, se versionan en Git (texto) y se reutilizan entre escenas.
- Ideal para: configuración de enemigos/armas/niveles, tablas de loot, parámetros de balance.
- Evitar constantes mágicas repartidas por el código.

## Gestión de estado

- **Máquina de estados** explícita para entidades complejas (jugador, enemigos, jefes). Implementación completa (clase base, `StateMachine`, input desacoplado y trampas) en `references/state-machine.md`.
- No usar `if estado == "..."` encadenados por todo el código.
- Para UI, separar la **escena de UI** de su **lógica**: un script contenedor que escucha señales y actualiza la vista.

## Transiciones y grupos

- Cambiar de escena con `get_tree().change_scene_to_file(...)` (carga en el mismo frame) o `change_scene_to_packed()` con `preload`.
- Preferir **una escena raíz persistente** (menú + mundo) antes que recargar todo, para conservar estado.
- Grupos (`add_to_group`, `get_tree().get_nodes_in_group`, `get_tree().call_group`) para operaciones sobre conjuntos (pausar enemigos, guardar todos).

## Errores comunes de arquitectura

| Error | Corrección |
|-------|-----------|
| Toda la lógica en un nodo raíz | Repartir en componentes con señales |
| Autoload "Manager" universal | Solo estado global; lo demás en escenas |
| `get_node` por strings largos | `%UniqueName`, `@onready`, señales |
| Datos de balance hardcodeados | `Resource` con `@export` |
| UI y lógica en la misma escena | Separar vista y controlador |
