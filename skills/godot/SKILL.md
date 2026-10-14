---
name: godot
description: Patrón senior para videojuegos en Godot 4 (GDScript y C#): escenas, nodos, señales, autoloads, recursos, rendimiento y exportación. Usar al crear, modificar o revisar un proyecto de Godot: gameplay, UI, física, input, guardado o build. NO para apps web ('angular'/'astro') ni APIs .NET ('dotnet') ni diseño visual ('ui-ux-mockup').
---

# Godot — Patrón senior

> Arquitectura de escenas, desacoplamiento por señales y rendimiento en Godot 4 (GDScript y C#). Criterios y anti-patrones; no es un tutorial de la interfaz.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| App web / sitio | `angular` / `astro` |
| API REST en .NET o MAUI | `dotnet` |
| Diseño visual de pantallas (antes de codificar UI) | `ui-ux-mockup` |

> **Frescura (verificado 2026-10-14):** **Godot 4.7.2** es la *stable* (2026-08-18); **4.8** está en desarrollo (estimado Q4 2026); 4.6/4.5 reciben solo correcciones. El build **.NET de 4.8 exige .NET 10** (sube desde .NET 8); en 4.7 el build C# usa **.NET 8**. Fuentes: `godotengine.org/download/archive`, `docs.godotengine.org/en/stable/about/release_policy.html`.

## Versión y elección de lenguaje

| | **GDScript** | **C# (.NET)** |
|---|---|---|
| Encaje | Nativo, sin build aparte, iteración rápida | Tipado fuerte, ecosistema .NET, equipos grandes |
| Requisito | Ninguno | Build **mono/.NET** + SDK .NET |
| Rendimiento | Suficiente salvo bucles intensivos | Mejor en cálculo puro; no en llamadas al motor |
| Recomendación | Por defecto para gameplay | Cuando ya hay C# o se necesita tooling .NET |

- **No mezclar ambos** en el mismo proyecto sin motivo fuerte: complica el build y el debugging. Elegir uno.
- Escribir **GDScript tipado** (con tipos) siempre que se pueda: mejor autocompletado, errores tempranos y rendimiento.

## Principios de arquitectura

1. **Composición, no herencia profunda.** Cada escena es un componente reutilizable; combinar escenas antes que heredar de una clase base grande.
2. **El motor es un árbol de nodos**: cada nodo hace **una** cosa. Un "god-node" que hace todo es el principal anti-patrón.
3. **Desacoplar con señales**: los hijos emiten, los padres escuchan (o suben por el árbol). Evitar que un nodo conozca rutas profundas de otros.
4. **Autoload solo para lo realmente global** (estado de juego, audio, un event bus). Si todo es singleton, se pierde todo el desacoplamiento.
5. **Datos en `Resource`** (`.tres`) con `class_name` y `@export`: configuración editable en el inspector y reutilizable, en lugar de constantes dispersas.

## Reglas y convenciones

- `@onready var nodo := $Ruta` para cachear nodos; **nunca** `get_node()` dentro de `_process`/`_physics_process`.
- Conectar señales en el editor o con `connect()`, nunca depender de nombres de nodo por string en cadenas largas.
- Input por **InputMap** (acciones), no por teclas crudas dispersas; usar `Input.get_axis`.
- Física en `_physics_process`; presentación/anima en `_process`. No mezclar.
- `queue_free()` (no `free()` directo) para liberar durante el frame.
- `.tscn`/`.tres` son **texto**: revisarlos en Git; evitar conflictos regenerando la escena.
- **Nombre de archivos y nodos** en el idioma/convención del proyecto, consistente; `class_name` en PascalCase.
- Para UI compleja, separar la lógica de la escena de UI (script en un nodo contenedor) en vez de un nodo "todo-en-uno".

## Anti-patrones / gotchas

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| Nodo "Dios" con toda la lógica | Imposible de testear/reutilizar | Composición + señales |
| `get_node("../../X")` con rutas fijas | Rompe al mover la escena | `@onready`, `%UniqueName`, señales |
| Autoload para todo | Acoplamiento global oculto | Solo estado realmente global |
| Lógica pesada en `_process` | Baja FPS | Cachear, usar señales/timers, precalcular |
| Crear objetos cada frame | Presión de GC / stutter | Reutilizar, object pooling |
| `yield` (Godot 3) | API eliminada | `await` |
| No liberar nodos | Fugas de memoria | `queue_free()` |
| Bloquear el hilo principal | Congela el juego | Tareas en hilo aparte o `WorkerThreadPool` |
| Cambiar el renderer sin motivo | Recompilar shaders, rompe efectos | Forward+ por defecto |

## Patrones

### Señal desacoplada (GDScript tipado)

```gdscript
class_name Health
extends Node

signal died
signal changed(current: int, max_value: int)

@export var max_value: int = 100
var current: int = 0

func _ready() -> void:
    current = max_value

func take_damage(amount: int) -> void:
    current = maxi(0, current - amount)
    changed.emit(current, max_value)
    if current == 0:
        died.emit()
```

### Instanciar escena y esperar una señal

```gdscript
const BULLET := preload("res://scenes/bullet.tscn")

func shoot() -> void:
    var bullet: Node2D = BULLET.instantiate()
    add_child(bullet)
    await get_tree().create_timer(1.0).timeout
    if is_instance_valid(bullet):
        bullet.queue_free()
```

### C# equivalente (señales y nodos)

```csharp
using Godot;

public partial class Health : Node
{
    [Signal] public delegate void DiedEventHandler();
    [Export] public int Max { get; set; } = 100;
    public int Value { get; private set; }

    public override void _Ready() => Value = Max;

    public void Damage(int amount)
    {
        Value = Mathf.Max(0, Value - amount);
        if (Value == 0) EmitSignal(SignalName.Died);
    }
}
```

## Rendimiento y export

- **Precalcular** en `_ready`, no en cada frame; evitar `get_node`, `instantiate` y asignaciones dentro de `_process`.
- **`preload`** para escenas/assets fijos; `load`/`ResourceLoader.load_threaded_request` para cargas bajo demanda.
- **Object pooling** en balas, partículas y enemigos de vida corta.
- **Export**: revisar `export_presets.cfg` (puede contener credenciales de firma) y `.gitignore` (`.godot/`).

## Checklist

- [ ] Lenguaje elegido (GDScript **o** C#), sin mezclar; GDScript tipado
- [ ] Escenas compuestas; sin nodos "Dios"
- [ ] Comunicación por **señales**; sin rutas `get_node` frágiles en runtime
- [ ] Autoloads solo para estado realmente global
- [ ] `_process` vs `_physics_process` según corresponda; nada pesado por frame
- [ ] Nodos liberados con `queue_free()`; sin objetos por frame
- [ ] Datos de diseño en `Resource` (`class_name`), no incrustados
- [ ] `.godot/` en `.gitignore`; `export_presets.cfg` revisado (secretos)
- [ ] Build/export probado en la plataforma objetivo

## Fuentes

- **Release policy**: `https://docs.godotengine.org/en/stable/about/release_policy.html`
- **Descargas / historial**: `https://godotengine.org/download/archive/`
- **Node / signals**: `https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/`
- **GUT (testing)**: `https://github.com/bitwes/Gut`
