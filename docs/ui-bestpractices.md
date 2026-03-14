# UI Best Practices — Master Reference

*Synthesized from Kole Jain, Mizko, and Apple WWDC design notes — updated 2026-03-05*

---

## Table of Contents

1. [[#Philosophy: Think Like a Product Designer]]
2. [[#Color System]]
3. [[#Typography & Hierarchy]]
4. [[#Layout & Spacing]]
5. [[#Component Patterns]]
6. [[#State Design]]
7. [[#Flows & UX Architecture]]
8. [[#Motion & Interaction]]
9. [[#Dashboard Design]]
10. [[#AI Product UI]]
11. [[#Mobile Interactions]]
12. [[#Platform-Specific: macOS]]
13. [[#Landing Pages & Marketing]]
14. [[#Avoiding AI-Generated UI Pitfalls]]
15. [[#AI-Assisted Design Workflows]]
16. [[#Presentation & Handoff]]
17. [[#Design System Fundamentals]]

---

## Philosophy: Think Like a Product Designer

**Real products win on completeness, not beauty.** A product that covers every state (empty, loading, error, success) and keeps users informed beats one with a stunning hero that falls apart everywhere else.

### Core Principles

- Design is not screens — it is **flows and decisions chained together**. Isolated beautiful mocks are not product design.
- The goal of UI is **directing attention and reducing friction**, not decoration.
- Every interaction must answer: *what does the user need to see/do right now?*
- Polish is a multiplier — it only matters after the flow works.
- "Modern" does not mean sterile. Personality and context are assets, not clutter.

### Intent-First Design

The "genius" move is mapping **what the user is trying to do** before touching visuals. Aesthetics (font, icon style, color) are secondary unless they improve comprehension or action-taking.

Before every screen design, answer:
1. **Primary user job** — what is the user here to accomplish?
2. **Decision-critical fields** — what info must be visible for the user to act?
3. **Required CTA** — what is the single most important next action?
4. **Progressive disclosure opportunities** — what can be hidden until needed?

Expand UI complexity only when user intent expands. Avoid premature feature/UI expansion.

### The Structure Pipeline (Apple WWDC25)

Design follows a strict order: **Structure > Navigation > Content > Visual Design.**

1. **Structure** — List everything the app does, map real usage context (when/where/why), prune until only essentials remain.
2. **Navigation** — Predictable movement, lower cognitive load, lean tab counts.
3. **Content** — Meaningful organization before aesthetics. Separate mixed content types into clear sections.
4. **Visual design** — Personality + usability, not decoration.

### The 3 Clarity Questions

Every screen must answer:
- **Where am I?**
- **What can I do?**
- **Where can I go from here?**

If these are unclear, users feel friction even when UI "looks good."

### Design for Edge Cases, Not Perfect Mocks

Two-step content design rule:
1. Decide which content is essential for scan decisions (e.g., location, rating, price).
2. Structure for **messy reality**, not perfect mock data:
   - Truncate long names safely
   - Maintain icon contrast on bright/variable imagery
   - Guard against edge-case layout breakage
   - Test with missing, odd, or extreme data

### Experience Design > Static Screens

In an AI-saturated landscape with many similar apps, differentiation comes from the **end-to-end product experience**, not isolated mockup polish:
- Motion/interaction quality
- Transitions and continuity between states
- Emotional feel and memorability of the whole journey

Design should be treated more like **directing a movie sequence** than composing isolated screenshots.

---

## Color System

### The 4-Layer Color Model (Replace 60/30/10)

The 60/30/10 rule is too blunt for product UI. Use a structured 4-layer system instead:

1. **Neutrals / Foundation** — background surfaces, borders, text tiers
2. **Functional Accent Ramp** — brand color with defined interaction states
3. **Semantic Colors** — success, error, warning, info
4. **Theming** — light/dark/branded variants via OKLCH transforms

### Neutral Layer Stack

Build multiple neutral layers — do not use a single background color:

- **Backgrounds:** ~4 layers (e.g., 99%, 100%, 98%, 96% white in light mode)
- **Borders/Strokes:** 1-2 values — avoid harsh black lines; use subtle edges (~85% white)
- **Text tiers:** 3 explicit levels
  - Headings: ~11% white (darkest)
  - Body: ~15-20% white
  - Subtext / muted: ~30-40% white

Never freestyle text grays. Define tokens. Stop hand-picking per screen.

**Dark mode:** Bump layer separation to ~4-6% (vs ~2% in light mode). Elevated surfaces should get **lighter** as they rise — counterintuitive but correct.

### Button Hierarchy Rule

> **"The more important a button is, the darker it is."**

- Primary CTA: darkest
- Secondary / multi-purpose: lighter (~90-95% white equivalent)
- Destructive: always semantic red, even if off-brand — clarity beats palette purity
- Disabled: desaturated

### Accent Ramp

Define a scale and wire it to interaction states consistently:

| State | Ramp Level |
|-------|-----------|
| Default | 500-600 |
| Hover | 700 |
| Links | 400-500 |
| Active / Pressed | 800+ |

Build matching ramps for light + dark — do not just invert.

### The "Data Gets Color" Rule

Accent color belongs in **charts, status indicators, and data visualization** — not random CTA buttons, nav icons, or decorative elements. Color should communicate meaning, not add energy.

### Semantic Colors

Define semantic swatches that are independent of the brand palette:

- Error/Destructive: red (semantic, not branded)
- Success/Confirm: green (semantic)
- Warning: amber
- Info: blue

These drop into modals, banners, and action dialogs without redesign.

Use **semantic system colors** (e.g., label/secondary backgrounds) for adaptive behavior across dark mode, contrast settings, and accessibility modes.

### OKLCH for Theming and Charts

- Use OKLCH to ensure perceived brightness is consistent across hues
- For chart color stops: hold lightness/chroma steady, step hue by ~25-30 degrees
- For dark/themed variants: convert neutrals via OKLCH > drop lightness by ~0.03 > increase chroma by ~0.02 > tweak hue

### Intentional Color (Simple Approach)

For teams starting out or simpler projects:
- Keep palette small (2-3 core colors max initially)
- Use opacity variants from one strong base color instead of inventing many unrelated colors
- Always check contrast (WCAG baseline)
- Shortcut for reverse-engineering palettes: Chrome DevTools `CSS Overview`

### What to Avoid

- Overly saturated accents with no semantic meaning
- Neon backgrounds — use tinted neutrals (gray + tiny hue) instead
- Pure black (#000) or pure white (#FFF) for text — use tiered grays
- Rigid brand palette with no expansion strategy
- Inverted dark mode — dark themes need bespoke palettes, not inverted light palettes
- Random color on buttons/icons just to add visual energy

---

## Typography & Hierarchy

### Type Scale Systems

Don't eyeball font sizes — use a systematic type scale:
- **Base paragraph:** ~16px
- **Heading scale:** ratio-based (e.g., major third ~1.25x)
- **Body line-height:** ~150%
- **Letter spacing:** default for body; tighten for larger headings
- **Tool:** `type-scale.com` for quick scale generation

### Core Rules

- **Never freestyle text grays.** Define three tokens: heading, body, muted — and use them everywhere.
- **Dashboards use tighter type scales** than marketing pages — adjust accordingly.
- **Hierarchy is the job.** Contrast, weight, and size should guide the eye to what matters next.
- Use **system text styles** for durable hierarchy and Dynamic Type support (especially on Apple platforms).
- When text overlays images, protect legibility with gradient/blur support.

### Animated Text (Marketing Only)

Use **animated keyword emphasis** sparingly in marketing/landing contexts — animate one key word in a headline (e.g., a progress bar fills then resolves into the word). The goal is attention direction, not complexity. One per section maximum.

### Microcopy

- Prefer friendly, natural language over corporate jargon
- Treat error states, empty states, and CTAs as copywriting opportunities
- Invest in edge copy: 404 pages, loading messages, success confirmations — these are the "invisible" touches users remember
- Use AI-assisted copy refinement for concise labels

---

## Layout & Spacing

### Core Rules

- **8pt spacing scale** — always. This is non-negotiable for perceived consistency.
- **Left alignment + consistent gutters** buys a disproportionate amount of perceived quality.
- **Strict grids for dashboards** — tighter than marketing; each module needs breathing room within a defined grid (2x2 or similar).
- **Predictable column systems by breakpoint:** 12 desktop / 8 tablet / 4 mobile.

### Build Scannability with Hierarchy Primitives

- Proximity
- Size
- Contrast
- Alignment

### Content Grouping Strategies

Reduce cognitive overload by grouping content intentionally:

- **By time** — recent, seasonal, date-based
- **By progress** — continue where you left off, completion status
- **By pattern/relationship** — related items, shared attributes

These patterns help users feel the product is "one step ahead."

### Breaking the Grid (Selectively)

Off-grid elements can add personality but require discipline:

- Off-grid elements must **pull attention toward the center** — they should trail off as they move away from the focal point
- "Eyeballing" is acceptable, but watch for angles/tilts that fight the composition
- Match energy to brand: playful blobs + bold colors vs. professional realism vs. doodles
- Keep **generous spacing around primary text** so surrounding context reads as support, not noise

### Progressive Disclosure

Default to showing less. Surface options when relevant:

- Advanced form options: collapsed by default, expandable
- Filters and settings: appear only when needed
- Low-frequency actions (settings, billing): grouped into a collapsed area or overflow menu
- Empty states: clean and instructional, not placeholder-heavy
- "Load more" can be better than infinite scroll when it preserves user control and footer access

### Sidebar Rules

- Group nav links by task — not by information category
- Icons + labels for collapsible states
- Push low-frequency items (settings, help, billing) to the bottom
- Use chips/badges sparingly — only for genuinely actionable status

---

## Component Patterns

### The Four Primitives (Cover 95% of Product UI)

| Primitive | Use |
|-----------|-----|
| Lists / Tables | Data display, bulk actions, multi-select |
| Cards | Grouped content, status, at-a-glance metrics |
| Input Surfaces | Forms, creation flows, search |
| Tabs | Sub-area navigation within a context |

### The Four Containers

| Container | When to Use |
|-----------|-------------|
| Popover | Quick, non-blocking tweaks (doesn't need full attention) |
| Modal | Complex task tied to current context (create, confirm, configure) |
| New Page | Deep dives requiring full focus |
| Toast | Non-blocking feedback (success/warn/error confirmations) |

Mix these deliberately. Never default to modals for everything. If navigating away, provide clear return context (breadcrumb/back).

### Card Hygiene

- No more than **one primary action** per card
- Consolidate secondary actions into an overflow (...) menu
- Collapse status chips into icons when they're purely indicators
- Put key metrics where scanning expects them (clicks/stats: right-aligned)

### Edge-Case Hardening for Cards & Lists

Run this pass on every data-driven component:
- Long titles: test with truncation
- Missing or odd data: what happens with null/empty fields?
- Contrast failures: icons on variable imagery or bright backgrounds
- Layout breakage: extreme data lengths, unexpected aspect ratios

### Forms

- **Sparse form in a huge canvas > use a modal** with progressive disclosure
- Break long forms into **titled groups** with helper text
- Right-size input fields: currency fields should be narrow; address fields wide
- **Strip signup funnels to mandatory fields only** — defer payments and plan selection until after account creation to avoid abandonment

### Icon Usage

- Use **one icon set** throughout (Phosphor, Lucide, or similar)
- Icons should be **semantic, not decorative** — every icon earns its placement
- Never use emojis as icons in professional UI unless intentionally brand-quirky (Notion-style)
- Prefer explicit labels + familiar iconography (SF Symbols on Apple) over vague naming
- Tag components in your design library so they're searchable by concept

### Account / Profile Surface

- Replace the common "gradient circle" avatar with a proper account card: name, email, org
- Use a popover menu for secondary account actions
- Collapse low-frequency items (settings, billing, usage) into a single grouped section

---

## State Design

Every feature must be designed for every state before dev picks it up. This is non-negotiable.

### Required State Matrix

| State | Description |
|-------|-------------|
| Empty | Teaches and prompts — what does the user do first? |
| Loading / Streaming | Progress indication, skeleton states, shimmer |
| Success | Inline confirmation, toast, status banner |
| Error | Friendly copy, recovery path, no dead ends |
| Permissions | What the user can't do and why |

### Patterns Per State

**Empty states:** Should not be blank. Provide:
- A clear prompt for the first action
- Optional contextual illustration that explains the product before reading
- No placeholder charts or fake data

**Loading states:**
- Stream text whenever possible
- Use skeleton placeholders with shimmer (not spinners alone)
- Short looping loaders make waiting feel like progress

**Success states:**
- Optimistic UI — assume success, animate immediately, roll back only on failure
- Toast confirmations for background actions
- Inline status banners (green "Account verified") instead of separate confirmation pages

**Error states:**
- Semantic red — always, regardless of brand color
- Recovery path is required — never leave the user stuck
- Friendly, specific copy — not "An error occurred"

**Notification surfaces:**
- Users need confirmation the system saw their action. Without it, they churn from confusion.
- Vercel-style deploy alerts, Slack-style status — these are trust infrastructure

---

## Flows & UX Architecture

### Think in Sequences, Not Screens

Design how someone **arrives**, what they **do**, and what the **next nudge** is. Micro-decisions chained together beat isolated artboards.

- Define **entry trigger** and **next action** for every flow
- Use modal > confirmation > optional branching — not flat screens
- Build in skip affordances where appropriate (onboarding, optional steps)

### Screen Reduction

> **Target <=5 steps before first value.**

- Combine congratulations pages with dashboards
- Reuse summary surfaces
- Ask "can this happen inline?" on every extra click
- Combine flows that are logically one task (e.g., create team space > add members immediately)

### The "Conversions First" Principle

For any page or flow with a conversion goal:
1. Resolve fit (can you solve my problem?)
2. Provide proof (have you done it before?)
3. Differentiate (why you?)

Every section should answer a buyer question — not just look good.

### Delay Paywalls

Push billing/plan selection until **after the aha moment** unless there's a security or regulatory reason. Premature paywalls are the #1 abandonment driver.

### Navigation Discipline

- Tabs are for **top-level navigation**, not action buttons
- Keep tab count lean — each extra tab increases decision burden
- Use toolbar title + contextual actions to restore orientation
- Respect common layout conventions (top nav, top-to-bottom, left-to-right flow, obvious CTAs) to reduce cognitive load
- Novelty should come from selective, high-value moments, not from breaking core layout expectations

---

## Motion & Interaction

### Core Rules

- Motion's job is **attention direction**, not visual interest
- Every animation needs: an easing curve, a settle state, and a purpose
- Avoid linear/robotic motion — use characterful easing
- Motion should **follow the action direction** (swipe right > element moves right)

### Entrance Animations

Prefer characterful entrances over generic fade-ins:

| Element Size | Pattern |
|-------------|---------|
| Small elements | Rotate + pop |
| Larger elements | Fly-in + slow bob |
| Cards / panels | Slide-in with elastic settle |

Add subtle parallax on scroll when margins are spacious — it makes the page feel alive without noisy backgrounds.

### Interaction Feedback Loops

- Keyboard shortcuts must have **visual confirmation** (panel slides, search bar expands, notification animates) or users assume failure
- Optimistic UI: animate success immediately; roll back on actual failure
- Hover tooltips, dimming inactive elements, and bulk action reveals all signal intentionality

### Text Motion

For marketing/landing pages — animate a **single key word** per headline:
- "deadlines" > progress bar fills, resolves into the word
- "paid" > dollar signs bounce, word drops in
- Use this sparingly — 1 per section maximum

### High-Commitment Actions

For destructive or irreversible actions, use **slide-to-confirm** instead of a modal:
- Reduces accidental taps
- Signals consequence clearly
- Faster than confirmation dialogs on mobile

---

## Dashboard Design

### The Sidebar as Spine

- One job: define where tasks live
- Group links by task flow, not by data category
- Collapsible with icons + labels
- Settings/help/billing always at the bottom
- Analytics in a dedicated tab, not sprinkled as sidebar stats
- Active states and optional nested groups/dropdowns
- Optional: contextual highlights/notifications in unused space

### The Hero Area Rule

Define the **one job** the dashboard solves. The hero area is:
- Creation controls + most critical metrics
- Nothing else

Everything else supports that single story. Avoid the "everything drawer" — surface what matters most at top.

### Charts

Simple and contextual always beats fancy:
- Axes, grid lines, range selectors, and quick summaries are required
- Hover states that dim inactive bars
- Pair chart + table for maximum clarity
- Chart colors via OKLCH so they don't read as Skittles
- Include range/date selectors and simple metric toggles

### Tables & Lists

Show only the essentials. Add:
- Multi-select > bulk action reveal
- Hover tooltips for truncated content
- Consistent favicon/icon column for identity
- Sorted defaults that match the user's likely intent
- Search/filter/sort for true utility (not just static data dumps)

### Interaction Polish

These make dashboards feel "enterprise-ready":
- Hover feedback on all interactive elements
- Optimistic delete/create (remove immediately, restore on failure)
- Toast confirmations for background operations
- Undo affordance where destructive actions are possible
- Perceived performance via optimistic UI (instant local response while server confirms)

### Dashboard vs Landing Page Distinctions

- **Tighter text scale range** than marketing pages
- **Stricter grid discipline** with denser but intentional data blocks
- **Decision-relevant columns only** — prefer stacked list/table clarity over unnecessary card clutter

---

## AI Product UI

Modern AI tools feel premium because of seven specific components working together. Adopt these as a reusable kit:

### 1. Prompt Box as Control Panel

- Full-width hero input that immediately invites interaction
- Attachment previews (PDF/images), compressed code blocks, mode chips
- Cost estimates, advanced mode toggles via progressive disclosure
- Deep integrations (Drive/GitHub/Figma) as optional affordances
- Fast animated feedback so the field feels like the product

### 2. Generation History + Memory Panel

Two distinct concerns — **history** (what happened) vs **memory** (what matters):

**History:**
- First-line preview for past runs
- Search across history/sessions
- Deletion controls

**Memory:**
- Expose saved memory clearly with add/view/delete controls
- Storage quota visibility
- Do not bury memory deep in settings — it should be a first-class surface

### 3. Inline Editing of Outputs

- Highlight a sentence > inline controls (rewrite, formalize, shorten)
- Keeps revisions local, avoids re-running whole prompts
- Keyboard shortcuts supported
- Feels like revision collaboration rather than re-prompting

### 4. Reasoning Trail ("Show Your Work")

- Step indicators: search > extract > draft (Perplexity-style)
- Animate each hop — builds trust and makes the UI feel alive
- Outputs feel *earned*, not hallucinated
- Makes intelligence legible and auditable

### 5. Latency UX

- Stream text character-by-character
- Skeleton states with shimmer placeholders during generation
- Short looping loaders — waiting should feel like progress

### 6. Confidence Indicators

- High/medium/low pills with numeric scores
- Drill-in affordance when results are shaky
- Treat it as safety instrumentation for the model
- Helps users calibrate trust and decide verification effort

### 7. Dark Soft-Glass Framing

The current AI aesthetic baseline:
- Blurred translucent cards (background blur)
- Gradient accents, subtle border shimmer
- 1px borders + inner shadows
- Subdued but luxurious — not neon
- Useful as a brand layer, but should remain secondary to clarity and legibility

---

## Mobile Interactions

### Three Types of Swipe

**1. Within-page navigation (swiping inside a screen)**
- Non-linear easing + bounce on settle — the bounce does most of the perceived-quality work
- Depth via perspective: slight card skew implies a 3D carousel
- Nearby items feel larger; edge items shrink
- Indicators must animate **fluidly** tracking intent — not just jump

**2. Between-page navigation (swiping to a different screen)**
- Goal is continuity — the user should feel the *same object* moving into a new context
- Card > full-screen expansion pattern:
  1. Expand the tapped card to fill the screen
  2. Slide in the next layer as it expands
  3. Elastic snap to seal the transition

**3. Swipe-as-action (gesture replacing a button)**
- Background responds: zoom/move slightly to reinforce depth as object "leaves"
- Slider confirmation for high-frequency destructive actions
- Motion always follows the swipe direction

### Motion Checklist for Every Mobile Interaction

Before shipping any gesture-based interaction:
- [ ] Easing curve defined?
- [ ] Settle state + micro-bounce specified?
- [ ] Indicator animates *with* user intent?
- [ ] Depth cues (scale/skew/blur) imply space?
- [ ] High-commitment action uses slider-confirm?

---

## Platform-Specific: macOS

### System-First Thinking

macOS apps should not be destinations — they should **surface where the user already is**:
- Hotkey-triggered overlays (Cmd+Shift+S style)
- Menubar helpers that appear, capture intent, disappear
- Spotlight-style command palettes

### Native Layout DNA

Apple's utilities share anatomy — respect it:
- Calm top bar (traffic lights as part of composition)
- Optional sidebar, content focus area
- Progressive disclosure: clean empty states, filters only when relevant
- Search: always present, collapsible until needed

### Color and Theme

- Light/dark mode need **bespoke palettes** — not inversions
- Dark mode: larger luminance gaps between layers
- Treat the app as a container for user content — keep chrome subdued, let content lead
- Desaturate logos slightly in dark mode

### Feedback Loops

- Optimistic UI: animate success immediately
- Every keyboard shortcut needs visual confirmation (panel slide, icon animation, toast) or users assume it failed
- Drag-and-drop should work from any surface to any compatible destination

---

## Landing Pages & Marketing

### The Client-Question Funnel

Structure every homepage to resolve three questions in order:

1. **Fit** — Can you solve my problem? (positioning copy, value prop)
2. **Proof** — Have you done it? (logos, testimonials, results)
3. **Differentiation** — Why you and not someone else?

Position this content above the fold. Everything else is below.

### Conversion Principles

- **Outcome-first storytelling:** replace clever visuals with plain-language results and measurable wins
- **2-click conversion:** push "book a call" over long intake forms; reduce friction to the minimum
- **Every claim needs visual evidence:** pair with a real screenshot, UI crop, or video — not just text
- **Boring layouts convert better:** minimal transitions, answer-first content outperforms flashy design for real buyers
- **One page = one primary goal:** clear CTA early (hero/nav) and repeated through scroll
- **Reinforce trust** via social proof (testimonials/reviews/logos)

### Question-Driven Sections

For each scroll band, ask: *"What would a buyer need here?"* Design to answer it:

| Section | Buyer Question |
|---------|---------------|
| Hero | Can you solve my problem? |
| Social proof | Have others with my problem worked with you? |
| Features/contents | What exactly do I get? |
| Fit | Is this for someone like me? |
| Live preview | Can I see it before committing? |
| Testimonials | What do real customers say? |
| FAQ | What's stopping me from saying yes? |

### Interactive Heroes

Prototype multiple hero concepts until one balances delight + clarity. A great hero:
- Proves taste immediately
- Still funnels to the conversion action
- Is interactive where possible — "Open preview" beats marketing copy

---

## Avoiding AI-Generated UI Pitfalls

AI-generated UI has predictable failure modes. Run this checklist on any AI-scaffolded screen:

### The Vibe Code Smell Test

- [ ] Emoji icons in nav, cards, or buttons?
- [ ] Neon palette or saturated accents with no semantic meaning?
- [ ] Same KPIs repeated in multiple places?
- [ ] Button soup on cards (more than one primary action)?
- [ ] Non-functional cards or controls that look interactive but do nothing?
- [ ] Pricing tiers over 4, hidden discounts, or no upgrade-delta copy?
- [ ] Landing page sections with icon grids and no substance?
- [ ] "Profile gradient circle" instead of a real account surface?

### The Fixes

| AI Failure | Correct Pattern |
|-----------|----------------|
| Emoji icons | Single semantic icon set (Phosphor/Lucide) |
| AI-picked color palette | 4-layer color system, "data gets color" rule |
| Repeated KPIs | Single hero metric strip, analytics tab for depth |
| Button soup | One primary per card, overflow menu for rest |
| Non-functional UI | Delete it — no exceptions |
| Giant canvas + sparse form | Modal + progressive disclosure |
| Gradient avatar | Account card (name/email/org) + popover |

### The "AI Detox" Starting Point

When working from an AI scaffold:
1. Swap all emoji icons for the standard icon set
2. Normalize the palette to 2-3 neutrals + 1 accent
3. Drop all placeholder charts (replace with real structure or remove)
4. Audit and delete non-functional components
5. Consolidate repeated information sections
6. Add overflow menus to any card with 2+ actions

---

## AI-Assisted Design Workflows

AI image models (e.g., Nano Banana Pro via Google AI Studio) are practical workflow accelerators — not replacements for design judgment. Treat outputs as **acceleration drafts**, not unquestioned final designs.

### 5 High-Value Use Cases

**1. UX Optimization Overlays**
- Input a screenshot of existing UI; prompt the model to annotate potential improvements directly on the image
- Good for fast heuristic passes on hierarchy, spacing, discoverability, and affordances
- Use as a critique layer before implementing in design tools

**2. Contextual Mockup Generation**
- Turn flat UI screenshots into scene-based product mockups (desktop on styled desk, tablet in field environment)
- Useful for portfolio/client storytelling without manual compositing

**3. Localization Ideation**
- Generate alternate versions for language/locale contexts (e.g., Japanese)
- Explores text treatment, content density, and regional visual conventions
- Not final localization QA — strong direction-finding tool

**4. Accessibility-First Revision Pass**
- Ask the model to suggest accessibility improvements (labels, navigation affordances, semantics)
- Creates an accessibility task backlog quickly before dev implementation
- Apply suggestions into working design files for iterative refinement

**5. Repeatable Creative Assets**
- Generate consistent visual variants from a base image (palette, branding, copy, mood changes)
- Useful for content systems, learning hubs, academy cards, and promo blocks

### Guardrails

Always keep human review on:
- UX logic and flow coherence
- Accessibility compliance (WCAG)
- Localization correctness
- Brand and legal consistency

Use model outputs to **expand option space quickly**, then converge via product constraints.

---

## Presentation & Handoff

### Presentation Styles

**Creative / Portfolio presentations:**
- Neutral/gentle backgrounds: darken the brand accent for light mode; use glow + gradient strokes for dark
- Minimalist hero shots: plain color wash + soft shadow — the UI is the hero
- Exploded frames: extend lines or components off-canvas (+/-2-14 degree skew) to imply motion
- Layered collages: offset screens, rotate slightly, zoom into a key section for variety
- Large landing-page sections work best for collage treatments; dense dashboards should be zoomed into key regions

**Client / Professional presentations:**
- Hardware mockups (laptop, tablet, phone, watch) — show the UI in context
- AI-generated lifestyle shots with specific props and lighting for fast contextual mockups
- **Prototype everything** — do not narrate interactions, show them
- Real states in the prototype — not Dribbble polish that doesn't reflect the product

### Two Output Modes per Iteration

Maintain two output packs for each major UI iteration:
1. **Showcase pack** — for social/portfolio/internal momentum
2. **Client/review pack** — realistic mockups + prototype clips

### The "Demo or Didn't Happen" Rule

Every interaction-heavy feature ships with a short prototype clip. Investors and hiring managers who click through real flows see product thinking. Static screenshots signal Dribbble drips.

### Dev Handoff Standards

Before handoff, every design file must have:
- Status chips on every section (Draft / WIP / Ready for Dev)
- Annotation kits with arrows explaining interactions and dev notes
- Responsive variants grouped per page
- Documented bespoke interactions (don't assume devs will infer behavior)
- Min/max width constraints on auto layout components

---

## Design System Fundamentals

A design system is not 200 components. It is a **set of decisions you refuse to re-litigate.**

### The Minimum System

| Token | Value |
|-------|-------|
| Spacing scale | 8pt base |
| Icon set | 1 library, semantic usage only |
| Surface palette | 2-3 neutrals + 1 accent |
| Text tiers | 3 tokens: heading / body / muted |
| Button semantics | Primary (safe) / Secondary / Destructive (red) / Ghost |
| Overlay hierarchy | Popover / Modal / Toast / New Page |

### Design System Sizing

Match system size to org reality:
- **Startup** — lean + flexible, define spacing/type/interaction rules
- **Large org** — extensive + rigidly defined
- The **process** of defining rules is as valuable as the final visuals
- Mature teams break rules intentionally, not accidentally

### Design Maturity Progression

Design quality follows predictable stages. At each level, the same core dimensions improve: **copy clarity, visual restraint, color balance, typography discipline, and spacing/system structure.**

| Level | Key Trait | Common Failure |
|-------|-----------|----------------|
| Beginner | Learning fundamentals | Overuse of color, random spacing, wordy copy |
| Junior | Better intent, cleaner visuals | Inconsistent systems, trend-chasing |
| Mid | Real clarity and hierarchy | Overworking visuals despite better taste |
| Senior | Strategic restraint, scalable systems | Still optimizing for static mockups over experiences |

The "post-senior" unlock: shifting from static screen polish to **designed product experiences** (motion, transitions, journey coherence).

### State Coverage Requirement

Before any new feature goes to dev, a **state matrix** is required:

| State | Designed? |
|-------|-----------|
| Empty | [ ] |
| Loading | [ ] |
| Success | [ ] |
| Error | [ ] |
| Permissions | [ ] |

### Design File Organization (Figma)

- **Status kit:** Draft / WIP / Ready for Dev tags on every section
- **Annotation kit:** Arrows + callouts explaining interactions inline
- **Breakpoint variables:** Store tablet/desktop/wide in local variables; switch via mode
- **Component tagging:** Tag icons/components with concept keywords so they're searchable
- **Auto layout on parent frames:** Wrap entire pages so sections rearrange with arrow keys
- **Variable timers:** Power interactive components (progress bars, looping states) without spaghetti prototyping

### When to Use Which Tool

| Scenario | Recommendation |
|----------|---------------|
| Product UI / complex component design | Figma |
| Marketing sites, fast ships | Framer (design + build in one pass) |
| Client prototype with real interactions | Figma + prototyping or Framer |
| Dev handoff for product | Figma with full annotation |

AI tools (prompt-to-edit, Figma AI) work best when modifying *existing* structure — not generating from scratch. Use them for boring variants and bulk edits; always verify design-system compliance.

---

*Sources: [[2026-02-23-kole-jain-4-ui-design-hacks-kill-boring-designs|4 UI Design Hacks]], [[2026-02-23-kole-jain-5-saas-ui-ux-mistakes-vibe-code|5 SaaS UI Mistakes]], [[2026-02-23-kole-jain-60-30-10-rule-ruining-ui-designs|60-30-10 Rule]], [[2026-02-23-kole-jain-7-color-mistakes|7 Color Mistakes]], [[2026-02-23-kole-jain-7-ui-components-unicorn-ai-startups|7 Unicorn AI Components]], [[2026-02-23-kole-jain-dashboard-ui-basics|Dashboard UI Basics]], [[2026-02-23-kole-jain-macos-app-design|macOS App Design]], [[2026-02-23-kole-jain-mobile-swipe-interactions|Mobile Swipe Interactions]], [[2026-02-23-kole-jain-present-ui-like-a-pro|Present UI Like a Pro]], [[2026-02-23-kole-jain-stop-making-pretty-uis-think-like-a-product-designer|Stop Making Pretty UIs]], [[2026-02-23-mizko-10-advanced-figma-hacks|10 Advanced Figma Hacks]], [[2026-02-23-mizko-framer-vs-figma-ai-beef|Framer vs Figma]], [[2026-02-23-mizko-launch-portfolio-in-5-days|Launch Portfolio in 5 Days]], [[2026-02-23-mizko-shipfaster-launch-breakdown|Shipfaster Launch Breakdown]], [[2026-02-23-mizko-stop-designing-like-this|Stop Designing Like This]], [[2026-03-05-how-to-think-like-a-genius-ui-ux-designer|Think Like a Genius Designer]], [[2026-03-05-the-only-5-web-design-skills-that-actually-matter-2026|5 Web Design Skills 2026]], [[2026-03-05-wwdc25-design-foundations-from-idea-to-interface|WWDC25 Design Foundations]], [[2026-03-05-4-levels-of-ui-ux-design-and-big-mistakes-to-avoid|4 Levels of UI/UX]], [[2026-03-05-7-ui-components-to-design-like-unicorn-ai-startups|7 AI Startup Components (Updated)]], [[2026-03-05-the-definitive-process-to-present-uis-like-a-pro|Present UIs Like a Pro (Updated)]], [[2026-03-05-everything-you-need-to-build-a-dashboard-ui-in-8-minutes|Dashboard UI in 8 Minutes]], [[2026-03-05-5-ways-nano-banana-pro-transforms-ux-ui-design-workflow|Nano Banana Pro Workflows]]*