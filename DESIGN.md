# Design System Specification: The Digital Darkroom

## 1. Overview & Creative North Star
The North Star for this design system is **"The Digital Curator."**

Unlike generic productivity tools, this system is designed to disappear, allowing the photographer's imagery to command the stage. We are moving away from the "boxy" nature of standard apps toward a high-fidelity, editorial experience. By utilizing macOS Sonoma's architectural patterns-sidebars, vibrant vibrancy, and toolbars-we create a workspace that feels like a physical light table.

We break the "template" look by leaning into **intentional tonal depth**. We do not use lines to separate ideas; we use light and shadow. The interface should feel like a single, cohesive piece of hardware where elements are etched or layered, rather than "pasted" on.

---

## 2. Colors: Tonal Depth & The "No-Line" Rule
This system utilizes a sophisticated palette of deep charcoals and adaptive grays to maintain focus on high-dynamic-range content.

### The "No-Line" Rule
**Explicit Instruction:** You are prohibited from using 1px solid borders to section the UI.
- Boundaries are defined solely through **Background Color Shifts**.
- To separate a sidebar from a main content area, place a `surface-container-low` section against the `background`.
- Structural integrity comes from tonal contrast, not outlines.

### Surface Hierarchy & Nesting
Treat the UI as a series of nested physical layers. Use the following tiers to define importance:
- **`surface_container_lowest` (#0e0e0e):** The "well" or "trough." Use this for the main image canvas to make photos pop.
- **`surface` (#131313):** The base application frame.
- **`surface_container_low` (#1c1b1b):** Primary utility areas (e.g., the Sidebar).
- **`surface_container_high` (#2a2a2a):** Hover states or secondary floating panels.
- **`surface_container_highest` (#353534):** Active selections or elevated popovers.

### The "Glass & Gradient" Rule
To achieve a premium "Pro" feel, main CTAs should not be flat.
- **Primary Action:** Use a linear gradient from `primary` (#adc6ff) to `primary_container` (#4b8eff) at a 145deg angle.
- **Floating Overlays:** Use `surface_variant` with a 70% opacity and a 30px backdrop-blur to create a "frosted glass" effect for tooltips and floating inspectors.

---

## 3. Typography: Editorial Precision
We use the system font, San Francisco (Inter), but with an editorial eye for metadata.

- **Display (Large Scale):** Use `display-md` (2.75rem) for empty state headers or splash moments. It should feel authoritative.
- **The Metadata Hierarchy:** Photography is data-heavy. Use `label-md` (0.75rem) in `on_surface_variant` for EXIF data (ISO, Shutter Speed).
- **The Title/Body Relationship:** Titles (`title-sm`) should be semi-bold to create a clear anchor point for the eye, while `body-md` remains regular weight for readability.
- **Contrast as Hierarchy:** Instead of increasing font size, use color. Primary labels use `on_surface`; secondary metadata uses `outline`.

---

## 4. Elevation & Depth: Tonal Layering
In this design system, depth is a result of light physics, not CSS properties.

- **The Layering Principle:** Stack surfaces to create lift. An Inspector panel (`surface_container_high`) sitting on the main workspace (`surface`) creates a natural, soft lift without needing a single shadow.
- **Ambient Shadows:** If an element must float (e.g., a context menu), use a shadow with a 32px blur and 8% opacity. The shadow color must be a tinted version of `surface_container_lowest` to feel like "trapped light" rather than a gray smudge.
- **The "Ghost Border" Fallback:** If a border is required for accessibility in high-density areas, use `outline_variant` at **15% opacity**. It should be felt, not seen.

---

## 5. Components: Precision Tools

### Buttons
- **Primary:** Gradient fill (`primary` to `primary_container`), `on_primary` text. Radius: `md` (0.375rem).
- **Secondary/Ghost:** No fill, `on_surface` text. On hover, apply `surface_container_highest`.

### Cards & Lists
- **Rule:** Zero divider lines.
- **Separation:** Use vertical whitespace (16px/24px) or a subtle background shift to `surface_container_low` on hover.
- **Image Thumbs:** Apply a `sm` (0.125rem) radius to thumbnails. A larger radius feels too "consumer"; a tight radius feels like a professional tool.

### Input Fields
- **Style:** `surface_container_lowest` background with a `Ghost Border`.
- **States:** On focus, the ghost border opacity increases to 100% using the `primary` color.

### Custom Component: The "Filmstrip"
- A horizontal scroll area using `surface_container_lowest`. Selected items are highlighted with a 2px `primary` underline-never a full box highlight, which obscures the image.

---

## 6. Do's and Don'ts

### Do
- **Do** use SF Symbols for all iconography to ensure macOS Sonoma native feel.
- **Do** lean into "Breathing Room." Sophistication is born from what you *don't* put on the screen.
- **Do** use `tertiary` (#ffb595) for "Warning" or "Flagged" states to provide a warm, high-end contrast to the cool blues.

### Don't
- **Don't** use pure black (#000000) or pure white (#FFFFFF). It breaks the sophisticated tonal range of the system.
- **Don't** use standard macOS default "Blue" for everything. Only use `Action Blue` (Primary tokens) for the singular most important task on the screen.
- **Don't** use "Drop Shadows" on buttons. If a button needs to stand out, use color luminosity, not elevation.
