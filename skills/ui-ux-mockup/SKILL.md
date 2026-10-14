---
name: ui-ux-mockup
description: Planificar y crear diseños UI/UX distintivos, guiados por referencias, y mockups previsualizables en el navegador antes de implementar. Usar al iniciar o rediseñar un sitio, landing, portafolio o app web con una dirección visual deliberada. NO para implementar frontend ('angular'/'astro') ni backend ('dotnet'/'fastapi').
---

# UI/UX Mockup — Primero el diseño, después la implementación

## Propósito

Crear sitios web con una identidad visual deliberada, una composición sólida y una razón clara detrás de cada decisión de diseño. No caer por defecto en layouts genéricos generados por IA ni en plantillas familiares tipo WordPress.

El primer entregable es una **dirección visual y un mockup aislado, previsualizable en el navegador**. La implementación en producción comienza solo después de que el usuario aprueba el diseño.

Esta skill es independiente del framework. Se puede usar con Astro, Angular, React, Vue, Svelte, HTML/CSS/JavaScript puro u otro stack ya elegido por el proyecto.

## Cuándo NO usar

| Situación | Skill |
|-----------|-------|
| Implementar el frontend (componentes, rutas, signals, SSR) | `angular` / `astro` |
| Backend o API | `dotnet` / `fastapi` |

Esta skill **decide y previsualiza el diseño**; la implementación en producción es de `angular`/`astro`.

## Principios centrales

1. **Diseñar para este proyecto, no para una tendencia.** Parte de la audiencia, el propósito, el contenido, la marca y el contexto.
2. **Usar las referencias para entender decisiones, no para copiar páginas.** Identifica los principios visuales que vale la pena aprender de cada referencia y adáptalos al proyecto actual.
3. **La distinción debe ser intencional.** Define una dirección de arte clara antes de elegir componentes o escribir el layout.
4. **Función y estética son socias.** El impacto visual no debe comprometer legibilidad, accesibilidad, rendimiento, navegación ni conversión.
5. **Prototipar antes de producción.** Mantén el mockup separado del código de producción hasta que el usuario lo apruebe.
6. **Explicar los trade-offs en lenguaje llano.** El usuario puede no tener formación formal en diseño; explica lo que importa y haz preguntas concretas.
7. **No afirmar verificación visual sin hacerla.** Si no puedes previsualizar en el navegador ni inspeccionar una captura, declara esa limitación.

## Anti-patrones

| Anti-patrón | Problema | Alternativa |
|-------------|----------|-------------|
| Layout genérico de IA (hero centrado, tres tarjetas, gradiente morado) | Irreconocible; parece plantilla | Dirección de arte anclada a la marca y el contenido |
| Copiar una referencia tal cual | No aporta identidad propia | Extraer el principio y adaptarlo al proyecto |
| Implementar en producción antes de aprobar el mockup | Retrabajo y decisiones a ciegas | Fase 7: implementar solo tras aprobar el diseño |
| Sacrificar legibilidad, contraste o accesibilidad por impacto | Excluye usuarios y rompe conversión | Función y estética socias; validar accesibilidad |
| Demasiados acentos visuales compitiendo | Ruido; nada destaca | Una idea fuerte; el resto en segundo plano |
| Afirmar "se ve bien" sin previsualizar ni capturar | Verificación inventada | Previsualizar o declarar la limitación |
| Depender de imágenes/video no disponibles | Layout roto o genérico | Diseñar con los assets reales o placeholders explícitos |

## Fase 1 — Entender el proyecto

Antes de diseñar, inspecciona el proyecto existente y las instrucciones relevantes, incluidos `AGENTS.md`, archivos de paquetes, estilos existentes, assets y skills propias del proyecto.

Establece, hasta donde la información disponible lo permita:

- Para qué sirve el sitio o la aplicación.
- Quién lo usará y qué necesita hacer.
- La acción o el recorrido de usuario más importante.
- La personalidad de la marca y cualquier identidad existente.
- El contenido, las imágenes, el video y los assets disponibles.
- Los dispositivos objetivo y los requisitos de accesibilidad.
- El stack tecnológico existente y sus restricciones.
- Qué conviene conservar, cambiar o evitar.

Pregunta solo lo esencial que siga sin respuesta. No hagas que el usuario complete un cuestionario de diseño largo si el repositorio o la conversación ya responden a casi todo.

## Fase 2 — Analizar referencias

Usa las referencias que el usuario aporte: sitios en vivo, capturas, moodboards, imágenes o archivos locales.

Para cada referencia relevante, analiza:

- **Dirección de arte:** el concepto visual general y el tono emocional.
- **Composición:** secciones a pantalla completa, asimetría, espaciado, escala y ritmo visual.
- **Tipografía:** jerarquía, carácter, legibilidad y uso de fuentes display.
- **Color y contraste:** paleta, overlays, contraste y énfasis.
- **Medios:** fotografía, ilustración, video, 3D, texturas y cómo sostienen el contenido.
- **Movimiento e interacción:** efectos de scroll, elementos fijos (pinned), transiciones, estados hover y navegación.
- **Arquitectura del contenido:** cómo se prioriza y se descubre la información.
- **Trade-offs prácticos:** accesibilidad, responsividad, rendimiento de carga y mantenimiento.

Registra qué aprender de una referencia y qué **no** copiar. No reproduzcas su layout exacto, su marca, sus textos, su arte ni sus assets distintivos, salvo que el usuario tenga los derechos y lo pida explícitamente.

Si un sitio no se puede inspeccionar, dilo. No inventes observaciones sobre su apariencia o comportamiento. Pide capturas o una descripción si la referencia es imprescindible.

### Ejemplos de referencias y posibles lecciones

Tómalas como puntos de partida, no como estilos obligatorios:

- **Tesla:** presentación de producto contenida, imagen con seguridad y jerarquía visual clara.
- **Rockstar Games / GTA VI:** dirección de arte cinematográfica, construcción de mundo y narrativa liderada por medios.
- **La Velada del Año:** identidad de evento, lenguaje gráfico fuerte y presentación de personalidades.
- **Study Together:** atmósfera, fondos inmersivos y medios integrados en una experiencia.
- **Bruno Simon:** un portafolio construido alrededor de un concepto interactivo memorable; úsalo solo cuando ese tipo de interacción sirva al proyecto.
- **Los proyectos del propio usuario:** evidencia útil del trabajo y las preferencias existentes. Analízalos individualmente en lugar de tomar uno como plantilla universal.

El usuario puede preferir una dirección original que no comparta el estilo superficial de ninguna de estas referencias. Eso es válido.

## Fase 3 — Definir la dirección de arte

Antes de construir el mockup, crea **tres direcciones de arte genuinamente distintas** cuando el alcance y la información disponible lo permitan. No presentes tres layouts casi idénticos que solo cambian de color.

Para cada dirección, define brevemente:

- Nombre e idea central.
- Sensación buscada y audiencia.
- Layout y composición.
- Enfoque de tipografía y color.
- Enfoque de imagen/video/ilustración.
- Enfoque de movimiento e interacción.
- Principales ventajas y riesgos.

Las direcciones posibles pueden ser editorial, cinematográfica, minimalista, expresiva, técnica, lúdica, premium, atmosférica o densa en contenido, pero elige según el proyecto, no según esta lista.

Recomienda la dirección más fuerte y explica por qué. Luego pide al usuario que elija o combine direcciones **antes de construir un mockup detallado**, salvo que ya haya autorizado explícitamente al asistente a elegir y continuar.

## Fase 4 — Construir un mockup aislado

Crea un prototipo independiente que el usuario pueda abrir y evaluar en el navegador.

### Ubicación y aislamiento

- Prefiere un directorio con nombre claro, como `design-preview/`, u otra ubicación acordada con el usuario.
- Inspecciona el repositorio primero; no sobrescribas ni reorganicen archivos existentes del proyecto.
- Mantén el mockup aislado del código de producción y evita cambiar el comportamiento de la aplicación.
- Si ya existe un prototipo propio del proyecto, reutilízalo solo cuando corresponda.

### Tecnología

- Por defecto, usa HTML, CSS y JavaScript semánticos para un mockup ligero e independiente del framework.
- Usa un framework o herramienta existente si mejora materialmente la previsualización, encaja con las restricciones del proyecto o el usuario lo pide.
- No instales dependencias solo para agregar novedad.
- Usa los assets disponibles del proyecto cuando corresponda; no reemplaces assets distintivos por imágenes de stock genéricas sin una razón.
- Si usas assets remotos, asegura un fallback razonable y explica cualquier dependencia de hosting externo.

### Calidad visual

El mockup debe demostrar la dirección visual buscada, no simples wireframes ni una colección de tarjetas genéricas.

Considera, cuando corresponda:

- Una composición hero distintiva.
- Jerarquía fuerte y espacios en blanco intencionales.
- Contraste significativo en escala, densidad y alineación.
- Un sistema tipográfico y una paleta deliberados.
- Imágenes o video relevantes y de alta calidad.
- Transiciones entre secciones y un ritmo visual coherente.
- Contenido realista en lugar de texto de relleno repetido.
- Detalles propios que conecten con la identidad del proyecto.
- Llamados a la acción claros y navegación comprensible.

No uses automáticamente:

- Un hero centrado con un titular genérico y dos botones.
- La misma grilla de tarjetas de tres columnas en cada sección.
- Gradientes morado/azul solo porque el proyecto es digital.
- Tarjetas flotantes tipo glass, esquinas muy redondeadas o botones pill por todos lados.
- Lenguaje SaaS genérico, estadísticas inventadas, testimonios falsos o badges sin sentido.
- Animación sin propósito.
- Un orden de secciones tipo plantilla, sin importar el contenido.

Estos patrones no están prohibidos cuando encajan de verdad; no deben ser la opción por defecto.

## Fase 5 — Movimiento, medios y efectos inmersivos

Elige interacción y movimiento para sostener el concepto y el contenido.

Técnicas posibles:

- Apariciones (reveals) disparadas por scroll.
- Secciones sticky o fijas (pinned).
- Parallax y profundidad por capas.
- Secciones visuales a pantalla completa.
- Video de fondo con un overlay estático.
- Sliders o carruseles.
- Microinteracciones y estados hover/focus intencionales.
- Transiciones sutiles entre secciones.

Usa librerías como SwiperJS, Font Awesome, Tailwind CSS, utilidades de animación de Tailwind, GSAP u otras herramientas solo cuando sean útiles y compatibles con el proyecto. Verifica las APIs reales y las versiones instaladas en lugar de asumir que un paquete está presente.

### Guía para video de fondo

Para experiencias atmosféricas, un video de fondo puede ser apropiado; por ejemplo, un sitio de tarot con luz de vela lenta, humo a la deriva o un cielo nocturno. Debe quedar siempre subordinado al contenido.

Al usar video de fondo:

- Prefiere material silenciado, en loop y no esencial; nunca hagas que el audio se reproduzca automáticamente.
- Agrega un overlay de contraste o un gradiente donde haga falta para que el texto sea legible.
- Asegura que los controles y el contenido en primer plano sigan siendo accesibles.
- Ofrece un póster o una imagen estática de respaldo, sobre todo para móvil y situaciones de pocos datos.
- Respeta `prefers-reduced-motion`; ofrece una alternativa estática cuando corresponda.
- Optimiza tamaño de archivo, resolución y codificación; evita videos grandes que retrasen el contenido relevante.
- No asumas que `background-attachment: fixed` se comporta igual en móvil. Prueba los navegadores objetivo y usa una capa de video fija u otro efecto si hace falta.
- Asegúrate de que el video sea decorativo, no la única forma de entender el contenido.

### Accesibilidad y responsividad

- Usa landmarks semánticos y un orden de encabezados coherente.
- Haz que la navegación y las interacciones sean accesibles por teclado.
- Proporciona estados de foco visibles.
- Mantén contraste de texto suficiente sobre imágenes y video.
- Evita movimiento que pueda causar incomodidad; respeta las preferencias de movimiento reducido.
- Diseña para pantallas angostas, touch y distintos tamaños de viewport.
- No escondas información esencial detrás de comportamiento solo-hover.

## Fase 6 — Inspeccionar e iterar

Antes de presentar el mockup:

1. Ejecútalo con un método de previsualización local disponible.
2. Inspecciona la página realmente renderizada en tamaños desktop y móvil cuando las herramientas lo permitan.
3. Revisa espaciado, recortes, tipografía, recortes de imagen, overlays, contraste y navegación.
4. Prueba los controles interactivos y los estados de error evidentes.
5. Revisa la salida de consola/build cuando esté disponible.
6. Corrige problemas visuales o funcionales claros antes de pedir al usuario que lo revise.

Si la inspección en el navegador no está disponible, entrega el mockup y declara claramente qué se verificó y qué no. Nunca afirmes haber probado un comportamiento que no probaste.

Pide feedback concreto usando conceptos visuales que el usuario pueda entender; por ejemplo:

- "¿El fondo tiene demasiada presencia?"
- "¿La página se siente demasiado corporativa?"
- "¿Quieres más espacio o más contenido visible?"
- "¿El movimiento aporta atmósfera o distrae?"

Haz los cambios de forma iterativa. Evita instrucciones vagas como "hazlo más moderno"; traduce el feedback en decisiones de diseño específicas.

## Fase 7 — Aprobación e implementación en producción

No portes el mockup a la aplicación de producción hasta que el usuario apruebe explícitamente la dirección, salvo que antes haya autorizado la implementación sin una aprobación separada.

Después de la aprobación:

1. Confirma el framework objetivo y las restricciones del proyecto si aún no están claros.
2. Traduce el sistema visual aprobado a design tokens y componentes reutilizables donde corresponda.
3. Reutiliza la composición, la tipografía, los colores, el tratamiento de medios y las interacciones aprobadas en lugar de rediseñar durante la implementación.
4. Sigue la arquitectura y las convenciones de código existentes del proyecto.
5. Asegura que la responsividad, la accesibilidad y el rendimiento se mantengan intactos.
6. Evita cambios de dependencias innecesarios o refactors amplios.
7. Compara la página de producción con el mockup aprobado y corrige desviaciones significativas.
8. Reporta qué se implementó, qué se probó y las limitaciones que queden.

## Entregables

Según la etapa del proyecto, entrega:

1. Un análisis conciso del proyecto y las referencias.
2. Tres direcciones de arte con una recomendación, cuando haga falta.
3. Un mockup aislado, previsualizable en el navegador.
4. Una explicación breve de las decisiones visuales.
5. Una lista de limitaciones conocidas o comportamiento no verificado.
6. La implementación en producción solo después de la aprobación.

## Estilo de trabajo

- Sé colaborativo y directo.
- No abrumes al usuario con jerga de diseño.
- Explica las decisiones de diseño en lenguaje llano.
- Haz una pregunta concreta por vez, salvo que realmente hagan falta varios detalles independientes.
- Prefiere pocas decisiones bien pensadas antes que una pila grande de efectos.
- El objetivo no es solo una captura bonita: es una experiencia distintiva, usable, accesible y mantenible.
