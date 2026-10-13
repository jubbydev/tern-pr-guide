# PR Guide

A Tern plugin (Luau and one stylesheet) with two surfaces: the PR hub organizes pull requests across repositories, and the guide walks through one pull request and posts one review.

## Product map

- `README.md` is the user manual and key reference.
- `GUIDE.md` is the saved guide-file contract.
- `docs/hub/README.md` is the PR hub's product and architecture spec. Before changing the hub, read **Product decisions**, **Shared Luau contracts**, **How this maps onto Tern** and **Verification**.

| Feature | Code |
|---|---|
| Hub columns, reasons and priority | `src/hub/model.luau` |
| Hub selection, filters, search and prepared board | `src/hub/state.luau` |
| Cache, refresh scheduling, recent PRs and merge settings | `src/hub/sync.luau` |
| GitHub commands and response parsing | `src/github.luau` |
| Processes, files, kv and worktree effects | `src/fetch.luau` |
| Hub actions, callbacks and window effects | `src/hub/block.luau` |
| Fixes page, agent fixes, review-before-push and summaries | `src/hub/fixes.luau`, `src/hub/agent-fix.luau`, `src/hub/review-fix.luau`, `src/hub/summary.luau` |
| Checks popover: groups, row times, the card's checks mark | `src/hub/checks.luau`, `src/view/hub/checks.luau` |
| Hub rendering | `src/view/hub/*.luau` |
| Saved guide model and parsing | `src/guide.luau` |
| Guided review interaction state and effects | `src/state.luau`, `src/review-page.luau` (the runtime, mounted at a root node path), `src/block.luau` (the `prguide.guide` block shell) |
| Guided review rendering | `src/view/*.luau` outside `src/view/hub/` |
| Model and lens menu (review page and hub Settings) | `src/model-box.luau`, `src/view/model-panel.luau` |
| Keyboard actions and help | `src/keys.luau`, `src/view/help.luau`, `src/view/hub/help.luau`, README Keys table |
| Shared presentation | `guide.css` |

## Where code goes

Each module's header comment names its one job. Put new code in the module that comment already covers. If none covers it, make a new module with its own header comment.

- **Host:** `src/host.luau` is the only module outside `src/view/` that reads `tern`. Its `Host` table holds the platform calls (processes, kv, files, JSON, timers, environment, clocks, the runtime's OS, plugin folders); other modules call `Host.kv.get(...)` and the like, and tests swap its fields. What differs by OS (home and temp folders, PATH lookup, the Python name, the link and folder opener) lives in `src/platform.luau`, which reads `Host.runtime` and `Host.getenv`; ask it rather than testing the OS or reading `HOME` or naming `/tmp` elsewhere.
- **Boundary:** only `src/fetch.luau`, `src/prdata.luau`, `src/agent-host.luau`, `src/tandem.luau`, `src/github.luau` and the CI modules in `src/ci/` reach outside the plugin. `fetch.luau`: the command runners on the reader's shell PATH (`Fetch.run`, `Fetch.git`, `Fetch.runner`), checkouts and saved copies, guide and lens files, opening a link in the system browser, and `Host.kv`. `prdata.luau`: reading a PR and posting a review with `gh` and `git`; its public functions are what the web port replaces with GitHub API calls. `agent-host.luau`: the reader's agent (`omp`) and agent fixes. `tandem.luau`: Tandem's CLI and database, plugin-only (the web port leaves it out). `github.luau`: GitHub, only through the runner it is given (`Fetch.runner` in the plugin). prdata, agent-host and tandem run commands only through fetch's runners.
- **CI logs:** `src/ci/log.luau` is the contract a CI module meets (`owns` a check, `read`s its log, `retry`s its failed checks) and knows no CI. Each CI is its own module that meets it, through the runner it is given: `ci/actions.luau` (GitHub Actions, `gh`), `ci/buildkite.luau` (Buildkite, `bk`). The modules never require each other; `hub/block.luau`'s `ciProviders` is the only place they meet. A new CI is a new module there.
- **Glue:** `src/review-page.luau` and `src/hub/block.luau` turn clicks and keys into one `ACTIONS` table. A new action is one `ACTIONS` entry, sent by both clicks and `keys.luau`. A hub action that is a workflow lives in the hub module for its job, and its entry calls it: `hub/ops.luau` (GitHub and agent actions on a PR), `hub/agent-run.luau` (an agent fix's flight), `hub/details.luau` (what the fixes and review fix pages read, failed-check logs included), `hub/tandem.luau` (Tandem's watch and hand-off, plugin-only), `hub/refresh.luau` (the probe, refresh and checks timers, and a PR's check list), `hub/prepare.luau` (background guides for review requests) and `hub/lookups.luau` (merge methods, flake evidence). They build on `hub/store.luau` (the shared cache and the Tandem ownership guard) and `hub/runtime.luau` (the `Block` record, drawing, frame ops, arrival alerts). Window effects go through `cx` and `Host.timer` only, and no module requires `hub/block.luau`.
- **Views:** `src/view/*.luau` turn state into nodes and nothing else, and may call `tern.ui`. Build them with `Ui.el` and `Ui.span`, and a text field's input with `Ui.field`.
- **Styles:** `guide.css` only, with `gp-` classes and the color tokens `DESIGN.md` names. To change a look, edit the rule where it lives.
- `GUIDE.md`, `prompts/explain.md`, `prompts/review.md` and `src/guide.luau` change together.
- `docs/port.md` is the hand-off for the TypeScript web port: every module's verdict, the seams as TypeScript, and each GitHub call. A change to a seam, a kv key or an `ACTIONS` entry updates it.
- Mockups and scratch files go in `/tmp`, except an approved design's reference mockups, which live with its spec (the PR hub's are in `docs/hub/`). A mockup links `docs/tern-tokens.css` (Tern's variable values), then `guide.css`, inside a `.gp-root` wrapper. `docs/screenshots/` is only for README images.

## UI

Read `DESIGN.md` and `docs/ui.md` before any change to `src/view/` or `guide.css`, and before making a mockup. `DESIGN.md` is the visual system: tokens, components, color meanings, and the interaction and density rules. `docs/ui.md` covers how to lay out new components, motion, and what Tern can't render. Before showing any UI to the user, run `docs/ui.md`'s "Before showing UI" checklist.

**Keyboard first.** A new control (button, field, tab, menu, toggle) ships with its keyboard path in the same change, mockups included:

- It has a key, listed in `view/help.luau` (the `?` panel) and the README Keys table, and shown as a `kbd` where `DESIGN.md`'s Keycaps section says.
- A menu or list opened by key works without the mouse: arrows (or `j`/`k`) move, ⏎ chooses, Esc closes, and a keyboard-opened menu appears without animation.
- The key and the click send the same `ACTIONS` entry.
- In the hub, letter keys act only while the search and add-by-link fields are empty, as `j` and `k` do.

## Copy

New UI text sounds official: neutral, plain and short, like GitHub.

| Kind | Pattern | Examples |
|---|---|---|
| Labels, buttons | Sentence case, verb first | "Mark all reviewed", "Request changes" |
| Progress | Present participle plus "…" | "Loading open pull requests…" |
| Failure | "Couldn't …: reason" | "Couldn't open your lenses folder" |
| Empty state | "No …" | "No description provided." |

- Prefer a noun over "you": "Needs attention", "Awaiting author".
- Plain statements: no exclamation marks, emoji or marketing words.
- In the same change, update the README.

## Verify

- `/opt/homebrew/bin/luau tests/run.luau` runs the pure-module tests and exits non-zero on a failed assert. Run it, then `tern plugin reload`.
- `tern plugin reload` exits 1 if the plugin fails to load.
- Try the change in Tern with **New PR Guide sample block**, or a real PR opened with `post=false`. Test reviews are always dry runs.
- For a change to the review page's layout, also open **New PR Guide worst-case sample block** at a wide and a narrow pane.
- Check UI changes in light and dark.

## Commits

The subject is the user-visible behavior as a plain sentence, with no type prefix. Example: "Picker: Recently opened PRs from any repo at the top, so a closed PR is one keypress away".

Main is the release: `tern plugin install github.com/jubbydev/tern-pr-guide` installs whatever main holds. Work on a branch, and bump `version` in `plugin.toml` in the change that lands on main: the patch number for fixes, the minor number for new features. `tern plugin install` and `tern plugin list` report that number, so an unchanged one looks like the update didn't install.
