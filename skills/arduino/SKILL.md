---
name: arduino
description: Firmware de Arduino para placas AVR (Uno/Nano/Mega) y ESP32/ESP8266 — sketches, GPIO, ADC/PWM, I2C/SPI, interrupciones, temporizadores no bloqueantes, memoria y bajo consumo. Usar cuando se escriba o revise un sketch o firmware, o se hable de placas Arduino/ESP32/ESP8266, sensores, actuadores, arduino-cli o PlatformIO. NO para el backend/API que consume los datos ('fastapi'/'dotnet') ni para diseñar la placa (esquemático o PCB), que es hardware.
---

# Arduino — Patrón senior

> Firmware para microcontroladores (AVR y ESP32/ESP8266): decisiones, patrones y anti-patrones; no es un tutorial de electrónica.

> **Frescura (verificado 2026-10-16):** toolchain citado: `arduino-cli` 1.5.1, Arduino IDE 2.3.10 y PlatformIO Core 6.2.0 (requiere Python ≥ 3.9). Cores: AVR **1.8.8** y ESP32 **3.3.12** (la 4.0 sigue en RC). Plataformas de PlatformIO: `atmelavr@5.3.0`, `espressif32@7.1.3`. Fuentes: `github.com/arduino/arduino-cli/releases`, `github.com/arduino/arduino-ide/releases`, `github.com/platformio/platformio-core/releases`, `github.com/espressif/arduino-esp32/releases`.

## Cuándo NO usar

| Situación | Skill / dónde |
|-----------|---------------|
| Backend, API REST o servicio que recibe los datos | `fastapi` / `dotnet` |
| Diseño de esquemático, PCB o layout | Hardware (fuera del catálogo) |
| Python/MicroPython/CircuitPython en la placa | Fuera del catálogo (aquí es C++ de Arduino) |

Esta skill es el **firmware del dispositivo**. El servidor que consume sus datos es `fastapi`/`dotnet`.

## Modelo de ejecución

- `setup()` corre **una vez** (configuración); `loop()` se repite **para siempre** (trabajo). Todo lo permanente (pines, buses, red) va en `setup()`.
- Nunca bloquear `loop()`: `delay()` detiene **todo** (lecturas, red, parpadeo). Programa con `millis()`.
- `millis()`/`micros()` devuelven `unsigned long`. Compara por **resta** (`millis() - t0 >= periodo`), segura al desbordar (~49,7 días en AVR).

## Decisiones y convenciones

- **No bloqueante**: tareas por intervalos con `millis()` y máquina de estados, nunca `delay()`.
- **Tipos de ancho fijo**: `uint8_t`/`uint16_t`/`uint32_t`; `unsigned long` para tiempo. `int` es **16 bits** en AVR (desborda a 32767).
- **Memoria (crítico en AVR)**: evita `String` (fragmenta el heap); usa `char[]` + `snprintf`. Literales a Flash con `F("...")`; constantes en `PROGMEM`.
- **Entradas**: `INPUT_PULLUP` para botones (activos a LOW) y **debounce** por `millis()`.
- **Interrupciones**: ISR **corta** (leer y marcar); variables compartidas `volatile`; en ESP32 marca la ISR `IRAM_ATTR` y no llames funciones no-IRAM. **En AVR `millis()` no avanza dentro de la ISR** (interrupciones deshabilitadas): no dependas de él para medir tiempo ahí (usa el contador del periférico).
- **ADC**: 10 bits en AVR (0–1023), 12 bits en ESP32 (0–4095). Nunca superes `Vref` (5 V AVR / 3,3 V ESP); ajusta con divisor o atenuación.
- **PWM**: `analogWrite` en AVR. En ESP32 usa `ledc` (`ledcAttach`/`ledcWrite` en core 3.x; `ledcSetup`+`ledcAttachPin` en 2.x).
- **Buses**: `Wire` para I2C (pull-ups de 4,7 k), `SPI` con `CS` explícito. No compartas un bus sin arbitrar.
- **Alimentación**: motores, servos y relés **nunca** del pin (20–40 mA); usa driver y fuente aparte con GND común. Una caída de tensión reinicia la placa.
- **Bajo consumo**: `sleep`/deep sleep, baja frecuencia y apaga radios; despierta por temporizador o interrupción.
- **Watchdog**: actívalo en producción (`wdt_enable`/`wdt_reset` en AVR; `esp_task_wdt` en ESP32) para reiniciar ante un cuelgue.

## Toolchain

### arduino-cli (code-first, apto para CI)

```bash
# El core ESP32 no está en el índice por defecto: registra la URL una sola vez.
# OJO: `config add` AGREGA al array -> re-ejecutarlo DUPLICA la URL. Para repetir sin
# duplicar: `arduino-cli config remove board_manager.additional_urls <url>` antes de añadir,
# o comprueba el estado con `arduino-cli config get board_manager.additional_urls`.
arduino-cli config add board_manager.additional_urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core update-index
arduino-cli core install arduino:avr@1.8.8 esp32:esp32@3.3.12   # @version = builds reproducibles
arduino-cli lib install "Adafruit BME280 Library"
arduino-cli compile --fqbn arduino:avr:uno ./mi_sketch
arduino-cli upload  --fqbn arduino:avr:uno -p COM3 ./mi_sketch
arduino-cli monitor -p COM3 -c baudrate=115200          # salida serial
```

FQBN típicos: `arduino:avr:uno`, `arduino:avr:nano`, `esp32:esp32:esp32`, `esp8266:esp8266:d1_mini`. Los puertos se listan con `arduino-cli board list`.

### PlatformIO (proyecto con dependencias fijadas)

```ini
; platformio.ini — fija la versión de plataforma (@x.y.z) para builds reproducibles.
[env:uno]
platform = atmelavr@5.3.0
board = uno
framework = arduino
monitor_speed = 115200

[env:esp32]
platform = espressif32@7.1.3
board = esp32dev
framework = arduino
monitor_speed = 115200
```

Sin `@version`, PlatformIO usa la última plataforma (rompe la reproducibilidad que pide el checklist); fija la que uses.

```bash
pio run                 # compila
pio run -t upload       # sube a la placa
pio device monitor      # abre el serial
pio run -t clean
```

## Anti-patrones / gotchas

| Anti-patrón | Problema | Solución |
|-------------|----------|----------|
| `delay()` en `loop()` | Bloquea todo; se pierden eventos y la red | `millis()` + máquina de estados |
| `String` en AVR | Fragmenta el heap → cuelgues aleatorios | `char[]`/`snprintf`, literales con `F()` |
| `int` para `millis()` | 16 bits en AVR → desborde | `unsigned long` |
| `millis() >= t` con signo | Falla al envolver | `(millis() - t) >= periodo` |
| Botón sin pull-up | Entrada flotante, lecturas erráticas | `INPUT_PULLUP` + lógica invertida |
| Botón sin debounce | Varias pulsaciones por una | Debounce por `millis()` o RC |
| `Serial.print`/`delay` en una ISR | Bloquea; se pierden interrupciones | Sacarlo de la ISR; marcar con `volatile` |
| Compartida sin `volatile` | El compilador cachea la variable | `volatile` (y `IRAM_ATTR` en ESP32) |
| Motor/servo desde el pin | Supera la corriente (20–40 mA) | Driver + fuente externa, GND común |
| Leer `WiFi` en bloque | Desconexiones y resets por watchdog | Sondeo no bloqueante + reconexión |
| `analogWrite` como DAC | Es PWM, no una tensión real | Filtro RC o DAC (ESP32) |
| Configurar pines en `loop()` | Reconfigura y pierde estado | Configurar todo en `setup()` |

## Patrones

### Parpadeo no bloqueante (base de toda tarea periódica)

```cpp
const uint8_t LED = 13;
unsigned long t0 = 0;
const unsigned long PERIODO = 500;  // ms
bool encendido = false;

void setup() { pinMode(LED, OUTPUT); }

void loop() {
  if (millis() - t0 >= PERIODO) {
    t0 += PERIODO;                 // incremento fijo: sin deriva acumulada
    encendido = !encendido;
    digitalWrite(LED, encendido);
  }
  // ... resto del trabajo, sin bloquear
}
```

### Botón con debounce

```cpp
const uint8_t BTN = 2;
bool estable = HIGH;
bool ultima  = HIGH;
unsigned long tCambio = 0;
const unsigned long DEBOUNCE = 30;  // ms

void setup() { pinMode(BTN, INPUT_PULLUP); }

void loop() {
  bool lectura = digitalRead(BTN);
  if (lectura != ultima) { tCambio = millis(); ultima = lectura; }
  if (millis() - tCambio >= DEBOUNCE && lectura != estable) {
    estable = lectura;              // flanco confirmado (LOW = pulsado)
  }
}
```

### Lectura I2C

```cpp
#include <Wire.h>
const uint8_t DIR = 0x76;           // direccion del sensor

void setup() { Wire.begin(); /* Wire.begin(SDA, SCL) en ESP32 */ }

void loop() {
  Wire.beginTransmission(DIR);
  Wire.write(0x00);                 // registro a leer
  if (Wire.endTransmission() != 0) { /* no responde: reintentar mas tarde */ }

  Wire.requestFrom((int)DIR, 1);
  if (Wire.available()) { uint8_t v = Wire.read(); (void)v; }
}
```

### Nodo de red sin bloqueos (ESP32)

```cpp
#include <WiFi.h>
unsigned long tReintento = 0;
const unsigned long ESPERA = 5000;  // ms

void setup() { WiFi.begin("ssid", "clave"); }  // no bloquea

void loop() {
  if (WiFi.status() != WL_CONNECTED && millis() - tReintento >= ESPERA) {
    tReintento = millis();
    WiFi.reconnect();               // reintento; nunca esperar en bloque
  }
  // ... resto del trabajo sigue corriendo
}
```

## Checklist

- [ ] `loop()` sin bloqueos (`millis()`, no `delay()`)
- [ ] Tiempo en `unsigned long`; comparación por resta
- [ ] Entradas con `INPUT_PULLUP` y debounce donde haga falta
- [ ] Sin `String` en AVR; literales con `F()`
- [ ] ISR cortas; `volatile` (y `IRAM_ATTR` en ESP32)
- [ ] ADC dentro del rango de `Vref`
- [ ] Actuadores con driver y fuente externa (GND común)
- [ ] Red/serial sin bloqueos; reconexión gestionada
- [ ] Watchdog y bajo consumo evaluados
- [ ] Toolchain reproducible (`arduino-cli`/PlatformIO con versiones fijadas)
