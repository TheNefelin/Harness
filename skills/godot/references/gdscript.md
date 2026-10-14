# Godot — GDScript tipado y C#

> Convenciones de scripting en Godot 4 y puente entre GDScript y C#.

## GDScript tipado

Escribir siempre con tipos: mejor autocompletado, errores tempranos y algo más de rendimiento.

```gdscript
class_name Player
extends CharacterBody2D

@export var speed: float = 200.0
@onready var sprite: Sprite2D = %Sprite

var _health: int = 100

func _physics_process(delta: float) -> void:
    var dir := Input.get_axis("move_left", "move_right")
    velocity.x = dir * speed
    velocity += get_gravity() * delta
    move_and_slide()
```

- Inferencia con `:=` cuando el tipo es evidente.
- `func nombre(a: int) -> void:` — declarar siempre el retorno.
- Evitar `Variant` (tipado dinámico) en el camino caliente.

## Anotaciones clave

| Anotación | Uso |
|-----------|-----|
| `@export` | Exponer en el inspector (con tipo y rango: `@export_range(0, 100)`) |
| `@onready` | Inicializar al entrar en el árbol (`@onready var x = $Nodo`) |
| `@tool` | Ejecutar el script también en el editor (usar con cuidado) |
| `@static_unload` | Liberar recursos estáticos de un script al descargarlo |
| `@warning_ignore` | Silenciar una advertencia puntual (justificarlo) |

## Señales, await y timers

```gdscript
signal finished(result: bool)

func run() -> void:
    await get_tree().create_timer(0.5).timeout
    finished.emit(true)
```

- `await` reemplaza el `yield` de Godot 3 (ya no existe).
- `await` funciona con señales, funciones que devuelven señales y con `Signal`.

## Ciclo de vida de nodos

| Método | Cuándo |
|--------|--------|
| `_ready()` | Nodo listo; los hijos ya existen |
| `_process(delta)` | Cada frame (presentación, animación, input de UI) |
| `_physics_process(delta)` | Paso fijo de física (movimiento, colisiones) |
| `_input` / `_unhandled_input` | Input; `_unhandled_input` para gameplay |
| `_enter_tree` / `_exit_tree` | Alta/baja del árbol |

No hacer trabajo pesado en `_process`/`_physics_process`; cachear y usar señales o `Timer`.

## Migración Godot 3 → 4 (lo que más rompe)

| Godot 3 | Godot 4 |
|---------|---------|
| `yield(obj, "sig")` | `await obj.signal` |
| `instance()` | `PackedScene.instantiate()` |
| `KinematicBody2D` + `move_and_slide(vel)` | `CharacterBody2D` + `velocity` + `move_and_slide()` |
| `Spatial` | `Node3D` |
| `export(Type) var` | `@export var` |
| `onready var` | `@onready var` |
| `connect("sig", self, "m")` | `sig.connect(method)` |

## C# esencial

- El proyecto necesita el build **.NET/mono** del editor y el SDK de .NET adecuado (4.7 usa .NET 8; 4.8 exige .NET 10).
- Clases `partial`, heredan del tipo de nodo; `override` de `_Ready`, `_Process`, `_PhysicsProcess`.
- Señales: delegado con sufijo `EventHandler` y `EmitSignal(SignalName.X)`:

```csharp
[Signal] public delegate void DiedEventHandler();
public void Die() => EmitSignal(SignalName.Died);
// conectar: Died += OnDied;
```

- Acceso a nodos: `GetNode<Sprite2D>("%Sprite")`; exportar: `[Export] public float Speed { get; set; }`.
- **Rendimiento**: minimizar llamadas C#→motor por frame; el marshalling de `Variant` tiene coste.

## Errores comunes

| Error | Corrección |
|-------|-----------|
| GDScript sin tipos | Anotar variables, parámetros y retornos |
| `yield` / `onready` sin `@` | Actualizar a API de Godot 4 |
| `free()` en medio del frame | `queue_free()` |
| Método conectado que ya no existe | Reconectar tras refactor (falla silencioso) |
| Mezclar GDScript y C# sin motivo | Elegir uno |
