---
name: PR Guide
description: GitHub pull request review inside Tern, read as an annotated story.
colors:
  ink: "var(--t1)"
  ink-secondary: "var(--t2)"
  ink-muted: "var(--t3)"
  ink-faint: "var(--t4)"
  line-faint: "var(--l1)"
  line: "var(--l2)"
  line-strong: "var(--l3)"
  line-hover: "var(--l4)"
  pane-glass: "var(--panel)"
  card: "var(--card)"
  chip: "var(--chip-bg)"
  shade: "var(--sf-shade)"
  gp-blue: "light-dark(#2f6fe0, #8ab4ff)"
  gp-blue-line: "light-dark(#4f86e8, #5b8ff0)"
  gp-blue-fill: "light-dark(#3b6fd8, #4a7ce0)"
  gp-blue-wash: "light-dark(#e9f0fc, #22304a)"
  gp-blue-wash-line: "light-dark(#c4d6f6, #34507e)"
  gp-blue-ink: "light-dark(#0b1f44, #ffffff)"
  gp-merge: "light-dark(#1f883d, #238636)"
  gp-merge-hover: "light-dark(#1a7f37, #2ea043)"
  gp-added: "light-dark(#1a7f37, #6fdd8b)"
  gp-success-wash: "light-dark(#eef8f0, #1d2e22)"
  gp-success-wash-line: "light-dark(#a6dcb4, #2f5a3a)"
  gp-removed: "light-dark(#cf222e, #ff7b72)"
  gp-danger-fill: "light-dark(#cf222e, #da3633)"
  gp-danger-text: "light-dark(#a40e26, #ff9a92)"
  gp-danger-wash: "light-dark(#fdf0ef, #33201f)"
  gp-danger-wash-line: "light-dark(#f0b4ae, #6b2f2b)"
  gp-changed: "light-dark(#9a6700, #e3b341)"
  gp-changed-wash: "light-dark(#fdf6e7, #332c1d)"
  gp-changed-wash-line: "light-dark(#ecd8a8, #5c4c2a)"
  gp-confirm: "light-dark(#bc4c00, #c9510c)"
  gp-suggestion: "light-dark(#8250df, #c297ff)"
  gp-suggestion-wash: "light-dark(#f3edfc, #2a2340)"
  gp-question: "light-dark(#0969da, #79b8ff)"
  gp-marker: "light-dark(#fff3c4, #3d3620)"
  guide-amber: "#d9822b"
  diff-added-row: "rgba(60,160,90,0.14)"
  diff-removed-row: "rgba(210,70,70,0.14)"
  diff-added-word: "rgba(40,190,90,0.40)"
  diff-removed-word: "rgba(230,60,60,0.40)"
  on-fill: "#ffffff"
typography:
  display:
    fontFamily: "var(--sans)"
    fontSize: "26px"
    fontWeight: 650
    lineHeight: 1.25
  headline:
    fontFamily: "var(--sans)"
    fontSize: "21px"
    fontWeight: 650
  display-sm:
    fontFamily: "var(--sans)"
    fontSize: "24px"
    fontWeight: 650
  headline-sm:
    fontFamily: "var(--sans)"
    fontSize: "20px"
    fontWeight: 650
  title:
    fontFamily: "var(--sans)"
    fontSize: "15px"
    fontWeight: 650
  body:
    fontFamily: "var(--sans)"
    fontSize: "15.5px"
    fontWeight: 400
    lineHeight: 1.55
  body-md:
    fontFamily: "var(--sans)"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  body-sm:
    fontFamily: "var(--sans)"
    fontSize: "13px"
    fontWeight: 400
  label:
    fontFamily: "var(--sans)"
    fontSize: "11.5px"
    fontWeight: 600
    letterSpacing: "0.06em"
  code:
    fontFamily: "inherit (Tern's terminal font)"
    fontSize: "12.5px"
    lineHeight: "19px"
rounded:
  mark: "2px"
  box: "4px"
  keycap: "5px"
  pill: "10px"
  chip: "var(--r-chip)"
  control: "var(--r-ctl)"
  card: "var(--r-card)"
spacing:
  hair: "2px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
  gutter: "28px"
  section: "36px"
components:
  button:
    backgroundColor: "{colors.chip}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "4px 12px"
  button-hover:
    backgroundColor: "{colors.line}"
  button-submit:
    backgroundColor: "{colors.gp-merge}"
    textColor: "#ffffff"
    rounded: "{rounded.control}"
    padding: "6px 8px 6px 14px"
  button-submit-hover:
    backgroundColor: "{colors.gp-merge-hover}"
  button-submit-confirm:
    backgroundColor: "{colors.gp-confirm}"
  card:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.card}"
    padding: "16px 20px"
  row-current:
    backgroundColor: "{colors.gp-blue-wash}"
    textColor: "{colors.gp-blue-ink}"
    rounded: "{rounded.control}"
  search-field:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "6px 10px"
  step-marker:
    backgroundColor: "{colors.gp-blue-fill}"
    textColor: "#ffffff"
    rounded: "8px"
    size: "15px"
---

# Design System: PR Guide

## Overview

**Creative North Star: "The Annotated Diff"**

PR Guide is a GitHub review that lives inside Tern. The frame belongs to Tern: its glass pane, its neutrals, its sans for prose and terminal font for code, its keycaps, tabs, icons and popovers. Inside that frame, GitHub's review meaning comes through unchanged. Blue marks where the reader is, green marks what was added and what gets submitted, red marks what was removed or is a problem, and orange asks for a second press before posting. The annotations come first: an overview and a margin of steps beside the code. The diff carries them.

The page is a reading instrument, not a dashboard. Text sits in a calm column on the left, code on the right, and color appears only where something needs the reader. Everything theme-dependent comes from Tern's variables, so the page follows any Tern theme the reader picks while staying recognizably a GitHub review.

Rejected looks: SaaS marketing gloss (gradients, decorative glass, glowing cards), IDE chrome overload (every toolbar and panel at equal weight), and off-brand GitHub (any color that contradicts what a GitHub reviewer expects, such as a non-green submit or a red approve).

**Key Characteristics:**
- Tern frame, GitHub meaning: two sources of color with a hard border between them.
- Neutrals are borrowed, never invented: text, lines and surfaces are Tern variables.
- Prose in Tern's sans, code in Tern's terminal font, never swapped.
- Flat by default. Depth comes from Tern glass on pinned surfaces and Tern's own overlay.
- Every action has a key, drawn with Tern's keycaps where the action applies.

## Colors

Two palettes with separate jobs: Tern's theme variables for everything structural, and a small pinned set of GitHub review colors for meaning. Each pinned color is a `light-dark()` pair declared once on `.gp-root` in `guide.css` as `--<key>` (the key below, e.g. `--gp-blue`).

### Primary
- **Review Blue** (`--gp-blue`, with `-line`, `-fill`, `-wash`, `-wash-line` and `-ink` variants): where the reader is. The current step's left bar and tint, the filled step number in the gutter, the current file's border and header wash, the selected search row, the "you" avatar, the comment `+`, the text caret and selection, and the jump ring. It stays this blue under every Tern theme. That's deliberate: a teal or orange theme accent must not move the reader's "you are here" mark.

### Secondary
- **Merge Green** (`gp-merge`, `gp-merge-hover`): the two things GitHub makes green, the Submit review button and the submit action. A ticked comment checkbox and a reviewed file's meter cell use it too.
- **Added Green** (`gp-added`, `gp-success-wash`, `gp-success-wash-line`): added-line counts, "added" state text, the posted-review notice, and the approve verdict once chosen.

### Tertiary
- **Removed Red** (`gp-removed`, `gp-danger-fill`, `gp-danger-text`, `gp-danger-wash`, `gp-danger-wash-line`): removed-line counts, the Problem comment kind, the request-changes verdict, and error notices (`gp-danger-text` on `gp-danger-wash`, for contrast).
- **Changed Amber** (`gp-changed`, `gp-changed-wash`, `gp-changed-wash-line`): the "changed" box in the before/after diagram, and running CI on a board card (the amber spinner beside the check count).
- **Confirm Orange** (`gp-confirm`): the submit button's second state, "Post to GitHub? Press ⌘⏎ again". Nothing else.
- **Comment kinds**: `gp-question` for Question and `gp-suggestion` for Suggestion, GitHub's own label hues. Nit uses `ink-muted`.
- **Agent Purple** (`gp-suggestion`, `gp-suggestion-wash`): the same hue marks an agent or Tandem working, as the agent status chip ("Waiting on Tandem"). The wash is a fixed `light-dark()` pair, never computed from the hue.
- **Marker Yellow** (`gp-marker`): lines being commented on and search hits in code. It overrides the add/remove tints.
- **Guide Amber** (`#d9822b`): the AI reviewer's avatar, as an identity color.

### Neutral
Default values for every Tern variable below are in `docs/tern-tokens.css`.
- **Ink** (`--t1`): titles, body, code, and hover text.
- **Ink Secondary** (`--t2`): supporting prose such as status text, step notes and the change "why".
- **Ink Muted** (`--t3`): labels, paths, line ranges, counts, gutters, and placeholder copy.
- **Ink Faint** (`--t4`): separators, dim hints, and checkbox outlines.
- **Lines** (`--l1` to `--l4`): `--l1` for hover fills, `--l2` for hairlines and pressed fills, `--l3` for control borders, `--l4` for hovered control borders.
- **Pane Glass** (`--panel`, with backdrop blur): every pinned surface, meaning the header, file headers and hint bar.
- **Card** (`--card`): panels, comment cards, the review side panel and the search field.
- **Chip** (`--chip-bg`): button rest fill and inline code.
- **Shade** (`--sf-shade`): quiet strips such as hidden-lines bars and the description header.
- **Syntax** (`--tk-keyword`, `--tk-string`, `--tk-function`, `--tk-type`, `--tk-number`, `--tk-comment`, `--tk-punct`): code tokens in diffs, the same palette Tern uses in its own code blocks.
- **Diff rows**: added `rgba(60,160,90,0.14)` and removed `rgba(210,70,70,0.14)`. Word-level changes are 0.40 alpha, and the current step's rows about 0.27. Translucent so they sit on any theme.

### Named Rules
**The Two Accents Rule.** Tern's accent is only for Tern's own parts: the tab underline and native list selection. Review meaning (current, added, removed, submit, confirm) is GitHub-pinned. Never put `--accent` on a review state or a GitHub color on Tern chrome.

**The Borrowed Neutrals Rule.** No hex gray in `guide.css`. A text, line or surface color is a Tern variable, or it is a pinned review color from the list above.

**The Spent Color Rule.** Color marks state: current, added, removed, needs action. Everything at rest is neutral.

**The Color Meaning Rule.** On boards and lists, a colored element means exactly one of these; anything else is neutral:

| Color | Means |
|---|---|
| Review Blue | your turn on someone else's PR, or "you are here" |
| Removed Red | your PR needs fixing |
| Added Green | done: approved, ready, passed |
| Suggestion Purple (`gp-suggestion`) | an agent or Tandem is working |
| Changed Amber | checks are running |

A wash of a meaning color on a control that doesn't carry that meaning (for example a blue "Next up" button) breaks the rule.

## Typography

**Body Font:** `var(--sans)`, Tern's UI sans (Geist, then the system sans)
**Code Font:** the reader's terminal font: inherited from the Tern surface, or `var(--tv-font)` where code sits inside sans prose (inline code in the PR description)
**Label Font:** the body sans, uppercase and tracked

**Character:** a quiet UI sans for explanation beside the reader's own terminal font for code. Paths, counts, line ranges and diagram boxes keep the terminal font because they're code-adjacent data.

### Hierarchy
- **Display** (650, 26px, 1.25): the change title in the sticky change card. The overview heading is 24px.
- **Headline** (650, 21px): the PR title. Panel titles such as "Finish your review" are 20px.
- **Title** (650, 15px): section titles in panels, the description head, and diagram titles at 16px.
- **Body** (400, 15.5px, 1.55): the change "why", capped at 820px. The overview summary is 16px at 1.5, and comment text is 14.5px at 1.5.
- **Body small** (400, 13–14px): status rows, file rows, list rows, notes, and hint bar labels at 12.5px.
- **Label** (600, 11.5–12px, 0.06em, uppercase): in-panel section labels such as "STEPS", "FILES CHANGED" and "CHANGE 1 OF 3".
- **Code** (terminal font, 12.5px, 19px rows): diff rows, gutters, and inline code.

### Named Rules
**The Two Voices Rule.** Explanation is sans and code is the terminal font. A string of code inside prose becomes an inline code chip, never a font switch in the middle of a word.

**The No Second Sans Rule.** Never declare a font stack. Prose uses `var(--sans)`, and code inherits.

## Layout

Flex only; Tern has no grid or floats. The guided page is two columns under a pinned header. On the left is the sticky change card (30% of the row, 240–380px, so it narrows before the code does), holding the change title, why, files and steps. It never runs past the hint bar: a long why or file list, then a long title, keeps three lines with a scroll of its own. On the right, the code column flexes and stacks excerpts 36px apart. The columns sit 28px apart. The Files view reuses that split with a pinned file tree, which scrolls on its own.

Spacing steps are 2, 4, 8, 12, 16, 24, 28 and 36px. Gaps inside a group are 2–8px, and gaps between groups are 16–36px. Rows that repeat (files, steps, search results, comments) are one line each, with counts in fixed right-aligned tabular columns. The page draws about 600 lines of code at most. Steps further away show just their file header.

Pinned surfaces: the header at the top of the page, file headers at 92px, the hint bar at the bottom, and the change card at 92px.

## Elevation & Depth

Flat by default. Depth comes from two places only, both Tern's. Pinned surfaces are Tern glass, meaning `--panel` with `backdrop-filter: blur(24px) saturate(1.2)`, so code scrolling underneath stays readable as a blur. Floating panels (the model and lens menu) are Tern's own `overlay` card, with Tern's shadow and pop. Everything else separates by spacing first, then hairlines (`--l2`), then a card fill.

### Named Rules
**The Glass Pin Rule.** Anything `position: sticky` gets Tern glass, never an opaque color picked to match.

**The No Homemade Float Rule.** Popovers are Tern overlays. The plugin draws no drop shadows of its own except the 1px lift on a chosen segment.

## Shapes

Gently rounded and consistent with Tern: `--r-chip` (6px) for chips, keycaps and small hover targets; `--r-ctl` (8px) for buttons, rows and fields; `--r-card` (12px) for panels, cards and the diagram. Smaller literal radii are reserved for marks: 2px for word highlights and meter cells, 4px for checkboxes. Avatars and step markers are full circles. Borders are 1px hairlines; the only thicker line is the current step's 3px inset bar, which is a state mark, not decoration.

## Components

### Buttons
Quiet and tactile, like Tern's own controls.
- **Shape:** control radius (`--r-ctl`).
- **Default:** chip fill (`--chip-bg`) with an `--l2` hairline, ink text, padding 4px 12px, 13px sans. Hover fills `--l2`.
- **Strong:** the same with weight 600, for the one primary action in a row, such as "Generate AI Guided Review".
- **Submit review:** Merge Green with white text, a count pill and its keycap. The confirm state turns Confirm Orange.
- **Press:** every pressable shares `scale(0.97)` over 120ms with `--gp-ease-out`.

### Keycaps
Tern's native `kbd` node. A key shows beside its action when the action belongs to what's selected (a card's split button, an open menu, a confirm). Board-wide keys show in the `?` panel and the control's tooltip instead, and the hint bar lists at most 5 keys. Single letters show upper-case, modifiers show glyphs (⇧ ⌘ ⏎ ⌃). Keycaps on a filled button invert to white at 35% opacity.

### View switch (Guided | Files)
Tern's native `tabs` node, with the `t` keycap beside it. Its underline is Tern's accent, the one place the theme accent appears.

### Cards and panels
- **Corner style:** `--r-card`.
- **Background:** `--card`, with an `--l2` hairline.
- **Padding:** 16px 20px (help and review panels at 20px 24px).
- **Comment card:** inset from the gutter (60px left), avatar plus the author line ("Tandem left a nit"), body at 14.5px, and a foot row of actions with their keys. Added cards take a success hairline, problem cards a danger hairline, the focused card a Review Blue hairline, and dismissed cards drop to 60% opacity.

### Code excerpt (signature)
A file block: a glass sticky header (caret, dimmed directory plus bold file name, line range, `+n −n` counts, "Show whole file", and a Reviewed check), then diff rows. Rows are a 40px gutter of old and new numbers, a sign, and code in the terminal font. Added and removed rows take the translucent diff tints, and word-level changes take a stronger tint with a 2px radius. Hidden runs collapse into a dashed shade bar ("26 unchanged lines"). A step's block starts at the line that opens its enclosing function; when that opener is more than 30 lines up, the bar above shows its text as a muted label instead. Code the PR only moved is neutral: `--l1` rows with a 2px `--l4` hairline on the left, never red or green, under a muted "Moved from src/a.ts:12" or "Moved to line 40" label set in the code columns. The current step's blue still wins over the gray. The current excerpt takes a Review Blue border and a blue-washed header. The current step's rows get a 3px Review Blue inset bar.

### Step outline (signature)
The left column's list of steps: a circle tick, the number, and the title. The current step sits in a Review Blue wash box with its note under it. A change of more than 7 steps lists the 5 around the current one, with muted "N earlier steps" and "N more steps" lines. Steps in a shared block also show a 15px numbered marker in the code gutter, filled Review Blue for the current one.

### Before / after diagram
A full-width card under the overview: one run through the code, a column per stage, with a Before row above an After row. Stage headings and row names use the Label style. Each box holds a name in the terminal font and a short note in the sans. Unchanged stages are one plain box across both rows. Changed and added boxes take their wash and line color (Changed Amber, Added Green); a removed box has a Removed Red sign and a dashed Removed Red line on a plain fill, without strike-through. A side that didn't exist shows a muted word instead of a box. The marked box ends its note with "Change N ›", which opens that change. Below the stages, a "Check" line in full-contrast sans names the consequence to confirm, and that stage is the diagram's one focal point: its heading carries Tern's `warn` icon and its marked box a full-contrast line. Text in the diagram clears 4.5:1 and its lines 3:1 against the surface they sit on, washes included. A wide diagram scrolls sideways.

### Review panel
A two-column card. On the left, comments grouped under file names: one row per comment with a tick, avatar, kind label, line link and text, and unticked rows at 50% opacity. On the right, a shade side card with the summary field, three verdict rows (Comment, Approve, Request changes, each with a colored circle icon and a keycap), and the Submit button. Chosen verdicts take their meaning color as a wash plus hairline.

### Search and recent rows
One-line rows at `--r-ctl`, hover `--l1`, selected Review Blue wash. Search rows lead with a fixed 70px kind column. Recently opened rows in the hub keep fixed repository, title and time columns.

### Model and lens menu
Tern's native `overlay`, anchored under the model button. At the top, an Explanation | Review segment switch with its `tab` keycap, and one muted line saying what the slot shown is for. Below, a search field, grouped model rows (on Review, an Off row first with its hint at the right), and a footer with effort segments, plus the lens segments on Review while the review is on. Segments are chip fills, and the chosen one is a card fill with a 1px lift. The model button reads explanation model, review model, each effort in `--t4`, then the lens.

The PR hub's Settings is the same menu in its own overlay under the settings button, followed by the "Open links in" toggle with its `L` keycap. It opens on Explanation with the search field focused, and saves the same choice as the review page.

### AI run rows
Under the status row. While the explanation runs and the page has nothing new to read, a busy row: the turning spark, "Explaining the changes…" written in once, an estimated progress bar in `--live`, and the clock. Once the guide shows and the review still runs, the row goes and the status row says "Reviewing for issues… 0:42" in `--t3`, where the lens and the waiting suggestions appear when it lands, so the header keeps its height. When the explanation failed and the review still runs, a quiet row instead: a still 12px spark in `--t3`, "Reviewing for issues…" at 13px in `--t2`, a 120px `--t4` bar, and the clock. The quiet row never animates beyond its bar's fill. The model button names each pass in `--t3` before its model ("Explain", "Review"), then the lens.

### Board card
Washed action cards: your-turn cards carry their meaning as a wash (Removed Red on your PRs, Review Blue on review requests), with the matching `-wash-line` hairline. Cards that wait take the shade fill, and a card in Inactive reads quieter still. Review cards show their size as `+additions −deletions` (Added Green and Removed Red, terminal font) on the meta line. One box per item, in this order: a chip line (the job, in its meaning color, with a short reason), the title, an optional note (what an agent found, or why a fix failed), and the meta line (repo #number, checks, age). Your-turn cards take their meaning color as a wash; waiting cards are neutral (`--sf-shade`); done cards take a green hairline and a ✓. The selected card takes a Review Blue outline. Selecting a card never changes its height.

### Card actions (split button)
A card's actions are one split button: the main action, with its alternatives behind an attached ▾. It's hidden at rest, appears quiet on hover (card fill, `--l3` hairline, ink text), and fills (with its key) on the selected card: Review Blue, or Merge Green on a Ready to merge card, with the keycap inverted to white at 35%. The ▾ shows only on the selected card. It is 22px high, takes the place of checks and age at the end of the meta line, so it never pushes other text or changes the card's height. There is one split button per card, always in that slot.

### Selection bar
When several items are selected, a bar sits at the top of their group: "N selected", the one action, and Clear (Esc). Its confirm lists at most 5 titles plus "and N more".

### Inline confirm
An action that can't be undone asks in place: one bold question line, a filled confirm button with ⌘⏎ (Confirm Orange, or Removed Red for deletion), and Cancel (Esc). No modal.

### Status chip
A short pill on a card's chip line that names the job or who the card waits on, never a sentence. On your-turn cards the first job's detail follows the chips as plain text in the card's meaning color ("Conflicts with main", "@maria-k asked 4h ago"). It is a `--r-chip` pill, 12px sans at weight 600, padding 0 7px. Fill follows the Color Meaning Rule:
- **Job for the reader:** solid fill with white text. Removed Red (`gp-danger-fill`) for a reason a PR needs fixes, one chip per reason ("Merge failed", "Checks failing", "Feedback", "Merge conflict"). Review Blue (`gp-blue-fill`) for "Review".
- **Waiting:** chip fill (`--chip-bg`) with `--t2` text ("Waiting on review", "You commented"). While checks run it holds the amber spinner.
- **Done:** `gp-success-wash` with Added Green text ("Approved").
- **Agent or Tandem:** `gp-suggestion-wash` with Agent Purple text ("Agent running", "Waiting on Tandem"). Agent progress is a still, one-line note below the title. Agent-capable cards reserve two 19px note rows with a 2px gap before starting: progress or the short commit on the first, the complete worktree path on the second (horizontally scrollable). Fix ready uses the Done chip. Lifecycle changes never animate the rows, keycaps or card height.

### Tabs with counts
The board's two tabs look like Tern's `tabs` node (13px sans, muted until active, a 2px underline in Tern's accent like the view switch), but are `gp-hub-tab` elements, because a native `tabs` node cannot carry a count and Tern's `sf-tab` rules don't style elements outside it. The count after the label is a Review Blue pill (`gp-blue-fill`, white text, 11px) and counts only the cards in the tab's your-turn column. A tab with none shows no pill.

### Boxes
A 14px square with a 4px radius for a choice that can be several. Empty it is a 1.5px `--t4` outline; chosen it is Review Blue filled with a white check. Used by the repository menu, and by selecting several cards later. A single choice shows only a Review Blue check.

### Menu rows
Rows in an overlay menu are `--r-ctl` rows, hover and keyboard cursor in `--l1` and Review Blue wash, a box or check first, then the label, then a muted count or hint at the right. Menus opened by a key draw without animation. The key panel (`?`) is an overlay with three columns of key rows: Move, The selected card, The board.

### Banner
One quiet line above a board for an item that spans the board (for example Next up): shade fill, `--l2` hairline, sized to its content and left-aligned, read left to right, ending in its action. Never a meaning-color wash.

New UI reuses one of these components or an earlier one in this section. A change that needs a new component adds it here first.

## Interaction and density

- **A click or ⏎ opens; ⌘-click or ⇧-click selects.** The cursor moves only when the reader moves it: nothing auto-selects or jumps on open.
- **Keys never animate.** Mouse-driven entrances may.
- **Every visible string changes a decision.** If a chip, header, column or card already says it, cut it. No explanatory notes for what the layout already shows.
- **Controls appear only where they act:** on the selected or hovered card, never on every card at rest.

## Do's and Don'ts

### Do:
- **Do** take every neutral from Tern: `--t1`–`--t4`, `--l1`–`--l4`, `--card`, `--chip-bg`, `--panel`, `--sf-shade`.
- **Do** keep review meaning on the pinned GitHub colors, identical under every Tern theme.
- **Do** make sticky surfaces Tern glass: `--panel` plus a backdrop blur.
- **Do** use Tern's native `kbd`, `icon`, `tabs` and `overlay` instead of drawing look-alikes.
- **Do** check every change in light and dark, and under a non-default Tern theme.
- **Do** keep code, paths and counts in the inherited terminal font, with tabular numbers in count columns.

### Don't:
- **Don't** write a hex gray, a font stack, or an opaque sticky background.
- **Don't** put `--accent` on a review state or a GitHub color on Tern chrome (The Two Accents Rule).
- **Don't** add gradients, decorative glass, glows, or drop shadows.
- **Don't** use text glyphs as icons where Tern has an icon (`check`, `chev`, `open`, `sparkle`, `warn`, `search`, file kinds).
- **Don't** stack panels at equal weight. A surface has one primary element, and the rest stays muted.
- **Don't** append override blocks (`v2`, `v3`). Change the rule where it lives.
