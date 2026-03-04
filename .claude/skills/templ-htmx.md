---
name: templ-htmx
description: Build UI pages and components using Go Templ, HTMX, Alpine.js, and Tailwind CSS
---

# Templ + HTMX Skill

The web frontend is a Go BFF (`platform-web`) using Templ for HTML components, HTMX for partial DOM swaps, Alpine.js for local state, and Tailwind CSS for styling. No JavaScript frameworks.

## File Locations

```
core/internal/web/
├── handler.go              # All HTTP handlers
├── router.go               # chi route registration
├── auth.go                 # WorkOS OAuth helpers
└── ui/
    ├── components/
    │   └── layout.templ    # Shell: header, nav, footer, theme toggle
    └── pages/
        ├── splash.templ    # / — marketing/home
        ├── about.templ     # /about
        ├── pricing.templ   # /pricing
        ├── templates.templ # /templates
        └── ...
```

Every `.templ` file has a generated `*_templ.go` counterpart. Never edit `*_templ.go` directly — it is always overwritten by `templ generate`.

## The Two-Component Pattern (Critical)

Every page must have exactly two Templ components:

```go
// Full page — rendered on direct navigation
templ SplashPage(userName string) {
    @layout.Shell(userName) {
        @SplashContent(userName)
    }
}

// Partial — rendered on HTMX swap
templ SplashContent(userName string) {
    <div id="main-content">
        // page body here
    </div>
}
```

The handler checks `isMainContentSwap(r)` and renders the appropriate component:

```go
func (h *Handler) handleSplash(w http.ResponseWriter, r *http.Request) {
    userName := getUserName(r)
    if isMainContentSwap(r) {
        pages.SplashContent(userName).Render(r.Context(), w)
        return
    }
    pages.SplashPage(userName).Render(r.Context(), w)
}
```

**Never skip the partial variant.** HTMX navigation breaks if only the full page exists.

## HTMX Navigation

Nav links use `hx-get` + `hx-target` + `hx-push-url`:

```html
<a hx-get="/about"
   hx-target="#main-content"
   hx-push-url="true"
   hx-swap="innerHTML">
    About
</a>
```

All swaps target `#main-content`. The `#main-content` div must be present in the shell layout.

## Icons (Lucide)

Use `data-lucide` attributes — icons are resolved at runtime via CDN:

```html
<i data-lucide="rocket" class="w-4 h-4"></i>
```

`lucide.createIcons()` is called on both `DOMContentLoaded` and `htmx:afterSwap`. Do not use SVG inline unless absolutely necessary.

## Styling Rules

### Geometry — Sharp, No Radius
```
rounded-none     ← everywhere (NEVER rounded-md, rounded-lg, rounded-full except status dots/avatars)
border           ← always visible
```

### Color Scale
| Context | Light | Dark |
|---|---|---|
| Background | `zinc-50` / `white` | `atom-bg` |
| Surface/card | `zinc-100` | `atom-surface` |
| Border | `zinc-200` | `atom-border` |
| Body text | `zinc-900` | `atom-fg` |
| Muted text | `zinc-400` / `zinc-500` | `atom-muted` |
| Accent blue | `blue-600` | `atom-blue` |
| Accent green | `green-600` | `atom-green` |

### Typography
- **Body/UI**: `font-sans` (Inter)
- **Code, terminal labels, section markers, CLI mockups**: `font-mono` (Roboto Mono)
- **Section label pattern**: `text-[10px] font-mono uppercase tracking-widest text-zinc-400 dark:text-atom-muted`

### Section Label Pattern
Every major section starts with a mono label above the `<h2>`:
```html
<p class="text-[10px] font-mono uppercase tracking-widest text-zinc-400 dark:text-atom-muted mb-2">
    // section-name
</p>
<h2 class="text-2xl font-bold">Section Heading</h2>
```

### Buttons
```html
<!-- Primary CTA -->
<button class="bg-white text-black px-6 py-3 text-xs font-bold uppercase tracking-widest border border-zinc-900 hover:bg-zinc-100">
    [ DEPLOY NOW ]
</button>

<!-- Secondary / outlined -->
<button class="border border-zinc-300 dark:border-atom-border px-6 py-3 text-xs font-bold uppercase tracking-widest hover:bg-zinc-50 dark:hover:bg-atom-surface">
    LEARN MORE
</button>
```

### Cards and Row Lists
```html
<div class="border border-zinc-200 dark:border-atom-border hover:bg-zinc-50 dark:hover:bg-atom-surface transition-colors p-4">
```
Gap between rows: `gap-3`. Separator grids: `gap-px bg-zinc-200 dark:bg-atom-border`.

### Hero / Dark Sections Grid Overlay
Apply inline background-image for the grid pattern on dark/hero sections:
```html
<section style="background-image: linear-gradient(rgba(255,255,255,0.03) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.03) 1px, transparent 1px); background-size: 32px 32px;">
```

## Copywriting Tone

Direct, systems-oriented, terminal aesthetic. Examples:
- `INITIALIZING PLATFORM...`
- `EXEC :: cargo build --release`
- `[ ENTER WORKSPACE ]`
- `// your-services`

No marketing fluff. No "powerful", "seamless", "effortless".

## Workflow After Edits

1. Edit `*.templ` file
2. Run `templ generate` (or let `task dev:web` watcher handle it)
3. Edit handler in `handler.go` if adding a new route
4. Register route in `router.go`
5. Run `go build ./...` from `core/` to verify

## Anti-Patterns

- **Editing `*_templ.go` directly**: Always overwritten by `templ generate`. Edit the `.templ` source.
- **Using `rounded-md` or `rounded-lg`**: Forbidden. Use `rounded-none` everywhere except status dots and avatars.
- **Skipping the Content partial**: Every page needs both `FooPage` and `FooContent`. Without the partial, HTMX navigation renders nothing.
- **Inline JavaScript beyond Alpine.js**: No script tags with logic. Use `x-data`, `x-show`, `x-on` for local state.
- **Using raw `<svg>` for icons**: Use `data-lucide` attributes instead.
- **Adding "forever free" or perpetual tier promises**: The free tier is generous but not a lifetime commitment. Do not write that language.
- **Exposing provider names (Hetzner, DigitalOcean) on user-facing pages**: Abstract infrastructure details like Vercel/Render do.
