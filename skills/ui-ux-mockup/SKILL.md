---
name: ui-ux-mockup
description: Plan and create distinctive, reference-driven UI/UX designs and browser-previewable mockups before implementing production websites. Use when starting or redesigning a website, landing page, portfolio, content site, or web application and the user wants a deliberate visual direction rather than a generic template.
---

# UI/UX Mockup — Design First, Implement Second

## Purpose

Create websites with a deliberate visual identity, strong composition, and a clear reason behind each design decision. Do not default to generic AI-generated layouts or familiar WordPress-style templates.

The first deliverable is a **visual direction and an isolated, browser-previewable mockup**. Production implementation begins only after the user approves the design.

This skill is framework-independent. It can be used with Astro, Angular, React, Vue, Svelte, plain HTML/CSS/JavaScript, or another stack already chosen by the project.

## Core principles

1. **Design for this project, not for a trend.** Start from the audience, purpose, content, brand, and context.
2. **Use references to understand decisions, not to copy pages.** Identify the visual principles worth learning from each reference and adapt them to the current project.
3. **Distinctiveness must be intentional.** Establish a clear art direction before selecting components or writing layout code.
4. **Function and aesthetics are partners.** Visual impact must not compromise readability, accessibility, performance, navigation, or conversion.
5. **Prototype before production.** Keep the mockup separate from production code until the user approves it.
6. **Explain trade-offs in plain language.** The user may not have formal design training; explain what matters and ask focused questions.
7. **Do not claim visual verification without doing it.** If browser preview or screenshot inspection is unavailable, disclose that limitation.

## Phase 1 — Understand the project

Before designing, inspect the existing project and relevant instructions, including `AGENTS.md`, package files, existing styles, assets, and any project-specific skills.

Establish, as far as the available information allows:

- What the website or application is for.
- Who will use it and what they need to do.
- The most important action or user journey.
- The brand's personality and any existing identity.
- The content, imagery, video, and assets available.
- The target devices and accessibility requirements.
- The existing technology stack and constraints.
- What should be preserved, changed, or avoided.

Ask only the essential unanswered questions. Do not make the user complete a long design questionnaire if the repository or conversation already answers most of it.

## Phase 2 — Analyze references

Use any references the user provides: live websites, screenshots, moodboards, images, or local files.

For each relevant reference, analyze:

- **Art direction:** the overall visual concept and emotional tone.
- **Composition:** full-screen sections, asymmetry, spacing, scale, and visual rhythm.
- **Typography:** hierarchy, character, readability, and use of display fonts.
- **Color and contrast:** palette, overlays, contrast, and emphasis.
- **Media:** photography, illustration, video, 3D, textures, and how they support the content.
- **Motion and interaction:** scroll effects, pinned elements, transitions, hover states, and navigation.
- **Content architecture:** how information is prioritized and discovered.
- **Practical trade-offs:** accessibility, responsiveness, loading performance, and maintenance.

Record what to learn from a reference and what **not** to copy. Do not reproduce its exact layout, branding, text, artwork, or distinctive assets unless the user has the rights and explicitly asks for that use.

If a site cannot be inspected, say so. Do not invent observations about its appearance or behavior. Ask for screenshots or a description if the reference is essential.

### Reference examples and possible lessons

Treat these as starting points, not mandatory styles:

- **Tesla:** restrained product presentation, confident imagery, and a clear visual hierarchy.
- **Rockstar Games / GTA VI:** cinematic art direction, world-building, and media-led storytelling.
- **La Velada del Año:** event identity, strong graphic language, and presentation of personalities.
- **Study Together:** atmosphere, immersive backgrounds, and media integrated into an experience.
- **Bruno Simon:** a portfolio built around a memorable interactive concept; use only when such interaction serves the project.
- **The user's own projects:** useful evidence of the user's existing work and preferences. Analyze them individually rather than treating one as a universal template.

The user may prefer an original direction that shares none of these references' surface styles. That is valid.

## Phase 3 — Define the art direction

Before building the mockup, create **three genuinely different art directions** when the scope and available information support it. Do not present three near-identical layouts with only different colors.

For each direction, briefly define:

- Name and central idea.
- Intended feeling and audience.
- Layout and composition.
- Typography and color approach.
- Image/video/illustration approach.
- Motion and interaction approach.
- Main advantages and risks.

Possible directions may include editorial, cinematic, minimalist, expressive, technical, playful, premium, atmospheric, or content-dense — but choose based on the project, not this list.

Recommend the strongest direction and explain why. Then ask the user to select or combine directions **before building a detailed mockup**, unless the user has already explicitly authorized the assistant to choose and proceed.

## Phase 4 — Build an isolated mockup

Create a standalone prototype that the user can open and evaluate in a browser.

### Location and isolation

- Prefer a clearly named directory such as `design-preview/` or another location agreed with the user.
- Inspect the repository first; do not overwrite or reorganize existing project files.
- Keep the mockup isolated from production code and avoid changing application behavior.
- If a project-specific prototype already exists, reuse it only when appropriate.

### Technology

- Default to semantic HTML, CSS, and JavaScript for a lightweight, framework-independent mockup.
- Use an existing framework or tool if it materially improves the preview, matches project constraints, or the user requests it.
- Do not install dependencies just to add novelty.
- Use available project assets when appropriate; do not replace distinctive assets with generic stock imagery without a reason.
- If using remote assets, ensure the prototype has a reasonable fallback and explain any dependency on external hosting.

### Visual quality

The mockup should demonstrate the intended visual direction, not merely wireframes or a collection of generic cards.

Consider, when appropriate:

- A distinctive hero composition.
- Strong hierarchy and intentional whitespace.
- Meaningful contrast in scale, density, and alignment.
- A deliberate type system and color palette.
- High-quality, relevant imagery or video.
- Section transitions and a coherent visual rhythm.
- Realistic content instead of repeated placeholder text.
- Custom details that connect to the project's identity.
- Clear calls to action and understandable navigation.

Do not automatically use:

- A centered hero with a generic headline and two buttons.
- The same three-column card grid for every section.
- Purple/blue gradients just because the project is digital.
- Floating glass cards, oversized rounded corners, or pill buttons everywhere.
- Generic SaaS language, invented statistics, fake testimonials, or meaningless badges.
- Animation that has no purpose.
- A template-like section order regardless of content.

These patterns are not prohibited when they genuinely fit; they must not be defaults.

## Phase 5 — Motion, media, and immersive effects

Choose interaction and motion to support the concept and content.

Potential techniques include:

- Scroll-triggered reveals.
- Sticky or pinned sections.
- Parallax and layered depth.
- Full-screen visual sections.
- Background video with a static overlay.
- Sliders or carousels.
- Microinteractions and intentional hover/focus states.
- Subtle transitions between sections.

Use libraries such as SwiperJS, Font Awesome, Tailwind CSS, Tailwind animation utilities, GSAP, or other tools only when useful and compatible with the project. Verify actual library APIs and installed versions instead of assuming a package is present.

### Background video guidance

For atmospheric experiences, a background video may be appropriate — for example, a tarot website using slow candlelight, drifting smoke, or a night sky. It must remain subordinate to the content.

When using background video:

- Prefer muted, looping, non-essential footage; never make audio autoplay.
- Add a contrast overlay or gradient where necessary for readable text.
- Ensure controls and foreground content remain accessible.
- Provide a poster or static image fallback, particularly for mobile and reduced-data situations.
- Respect `prefers-reduced-motion`; provide a still alternative when appropriate.
- Optimize file size, resolution, and encoding; avoid large videos that delay meaningful content.
- Do not assume that `background-attachment: fixed` behaves consistently on mobile. Test the target browsers and use a fixed video layer or an alternative effect if needed.
- Make sure the video is decorative, not the only way to understand the content.

### Accessibility and responsiveness

- Use semantic landmarks and sensible heading order.
- Make navigation and interactions keyboard accessible.
- Provide visible focus states.
- Maintain sufficient text contrast over images and video.
- Avoid motion that can cause discomfort; honor reduced-motion preferences.
- Design for narrow screens, touch, and different viewport sizes.
- Do not hide essential information behind hover-only behavior.

## Phase 6 — Inspect and iterate

Before presenting the mockup:

1. Run it using an available local preview method.
2. Inspect the actual rendered page at desktop and mobile sizes when tools permit.
3. Check spacing, clipping, typography, image crops, overlays, contrast, and navigation.
4. Test interactive controls and obvious error states.
5. Check console/build output when available.
6. Fix clear visual or functional problems before asking the user to review it.

If browser inspection is unavailable, provide the mockup and clearly state what was and was not verified. Never claim to have tested a behavior that was not tested.

Ask for concrete feedback using visual concepts the user can understand, for example:

- “¿El fondo tiene demasiada presencia?”
- “¿La página se siente demasiado corporativa?”
- “¿Quieres más espacio o más contenido visible?”
- “¿El movimiento aporta atmósfera o distrae?”

Make changes iteratively. Avoid vague instructions like “make it modern”; translate feedback into specific design decisions.

## Phase 7 — Approval and production implementation

Do not port the mockup into the production application until the user explicitly approves the direction, unless they previously authorized implementation without a separate approval.

After approval:

1. Confirm the target framework and any project constraints if not already clear.
2. Translate the approved visual system into reusable design tokens and components where appropriate.
3. Reuse the approved composition, typography, colors, media treatment, and interactions rather than redesigning it during implementation.
4. Follow the project's existing architecture and coding conventions.
5. Ensure responsive behavior, accessibility, and performance remain intact.
6. Avoid unnecessary dependency changes or broad refactors.
7. Compare the production page against the approved mockup and correct meaningful deviations.
8. Report what was implemented, what was tested, and any remaining limitations.

## Deliverables

Depending on project stage, provide:

1. A concise project/reference analysis.
2. Three art directions with a recommendation, when needed.
3. An isolated, browser-previewable mockup.
4. A short explanation of the visual decisions.
5. A list of known limitations or unverified behavior.
6. Production implementation only after approval.

## Working style

- Be collaborative and direct.
- Do not overwhelm the user with design jargon.
- Explain design choices in plain language.
- Ask one focused question at a time unless multiple independent details are genuinely required.
- Prefer a small number of thoughtful decisions over a large pile of effects.
- The goal is not merely a pretty screenshot: it is a distinctive, usable, accessible, and maintainable experience.
