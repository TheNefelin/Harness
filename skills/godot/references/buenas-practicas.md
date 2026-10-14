# Godot — rendimiento, input, guardado, testing y export

> Prácticas para que el juego rinda, se pueda testear y se exporte sin sorpresas.

## Rendimiento

- **No trabajar por frame**: cachear en `_ready`, usar `@onready`; nada de crear objetos, `get_node` ni `instantiate` dentro de `_process`.
- **`preload`** para escenas/recursos fijos; **`ResourceLoader.load_threaded_request`** para cargas pesadas sin bloquear.
- **Object pooling** para balas, partículas, daños flotantes, enemigos de vida corta: reciclar en vez de crear/destruir.
- **Desactivar lo invisible**: `VisibleOnScreenNotifier2D` + `set_process(false)`/`set_physics_process(false)`.
- **`Tween`** en lugar de interpolaciones manuales por frame; **`MultiMesh`** para muchas instancias idénticas.
- **Muchos nodos iguales** → reducir profundidad del árbol y evitar señales por nodo; usar grupos y procesamiento por lotes.
- Perfilar con el **profiler/monitor** del editor antes de optimizar. No optimizar a ciegas.

## Input y física

- Definir acciones en **InputMap** (`Project Settings → Input Map`); usar `Input.get_axis("left", "right")` y `Input.is_action_pressed`.
- Lógica de juego en **`_unhandled_input`** (deja que la UI consuma primero); no mezclar con `_input` global.
- Cuerpos: `CharacterBody2D/3D` con `move_and_slide()` para personajes; `RigidBody` para físicas reales; `Area2D/3D` para triggers y detección.
- **Capas y máscaras de colisión** bien definidas: evitan colisiones no deseadas y mejoran el rendimiento.
- Raycasts: nodos `RayCast2D/3D` o `PhysicsDirectSpaceState` fuera del bucle por frame.

## Guardado y carga

- Ruta de usuario: `user://` (nunca escribir en `res://`, que es de solo lectura al exportar).
- **Datos guardados = datos serializables**: nunca guardar referencias a nodos; guardar **IDs** y reconstruir al cargar.
- Formato: **`Resource`** + `ResourceSaver`/`ResourceLoader` para lo tipado, o **JSON** (`JSON.stringify`/`JSON.parse_string`) para lo simple y portable.
- Versionar el formato de guardado (un campo `version`) para migrar partidas viejas.
- Cifrar/obfuscar si hay progreso sensible; el guardado en claro es manipulable.

## Testing

- **GUT** (Godot Unit Test) o **GdUnit4** como addon.
- Test de lógica pura (cálculos, máquinas de estado, inventario): fácil y valioso. Testear nodos que requieren el árbol es más frágil; usar `await` a `_ready`.
- Ejecución:

```bash
# GUT por línea de comandos (ajusta el runner a tu versión de GUT)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test -gexit
```

- No cargar escenas completas para probar una función: extraer la lógica a código testeable (sin nodo) cuando sea posible.

## Control de versiones

`.gitignore` recomendado para Godot 4:

```gitignore
.godot/
/android/
*.translation
```

- **Sí** versionar `.tscn` y `.tres` (son texto).
- **Revisar `export_presets.cfg`**: puede contener rutas y credenciales de firma; no subir keystores ni contraseñas.
- Archivos grandes (texturas, audio, vídeo): valorar **Git LFS**.
- Evitar conflictos en `.tscn`: no editar la misma escena desde dos ramas; regenerarla si se corrompe.

## Export

- Instalar **export templates** y definir presets por plataforma.
- Probar el build **en la plataforma objetivo**, no solo en el editor.
- Revisar: **renderer** (Forward+/Mobile/Compatibility), **rendering method**, tamaño del paquete y permisos (Android/iOS).
- Los scripts con `@tool` y los `res://` a `user://` son los puntos que más rompen al exportar.

## Errores comunes

| Error | Corrección |
|-------|-----------|
| Trabajo pesado en `_process` | Cachear; usar señales/timers |
| Crear/destruir objetos por frame | Object pooling |
| Guardar en `res://` | Usar `user://` |
| Guardar referencias a nodos | Guardar IDs y reconstruir |
| Subir `.godot/` o keystores | `.gitignore` + no commitear secretos |
| Testear todo con el árbol completo | Extraer lógica pura y testearla |
