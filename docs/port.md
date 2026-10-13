# How to port PR Guide to a hosted TypeScript web app

This guide is for the agent that turns this Tern plugin into a hosted TypeScript web app that calls the GitHub API with a token. It names what to keep, what to replace and what to leave out, and in what order. The appendices are reference: every module, every seam as a TypeScript interface, every action and every test.

Read the code when this guide and the code disagree. The code is the spec.

## What the app is

PR Guide turns a GitHub pull request into a guided review and gives the reviewer a board of every open pull request that needs them.

- The guide page walks a PR change by change, from a guide file an AI agent writes, and posts the review to GitHub. [README.md](../README.md) is the user manual.
- A guide file is JSON with steps over the diff. [GUIDE.md](../GUIDE.md) is its contract.
- The PR hub is a board of the viewer's PRs and review requests, with merges, queues, branch updates, re-runs, replies and agent fixes. [docs/hub/README.md](hub/README.md) is its spec.
- [DESIGN.md](../DESIGN.md) and [docs/ui.md](ui.md) are the visual system: tokens, components, motion and density.

## Decisions already made

- The app is hosted. It is a TypeScript web app, not a desktop plugin.
- It talks to GitHub through the REST and GraphQL APIs with a token. Production has no `gh` CLI.
- It has no Tandem. Tandem is a separate PR-fixing service that the plugin hands branches to. [Leave out Tandem](#leave-out-tandem) lists what that removes.

The port keeps these features:

- The guided review and AI guide generation (`omp` writes the guide).
- The hub board: columns, tabs, sort, filter, search, add by link, Settings, the fixes page (with failed-check logs from GitHub Actions and Buildkite) and the review fix page.
- GitHub operations: merge (squash, merge, rebase, queue, a comment command, a label), merge when ready, cancel merge, batch merge and batch close, Update branch, re-run failed checks, re-request review, close, reply to a thread and resolve a thread.
- Shared cache sync. In the plugin, several windows share one board cache. In the web app, the same rules cover several tabs, and several users of one board if you choose to share it.
- Agent fixes: an agent resolves merge conflicts or bot feedback in a worktree, the reviewer checks the result, and the app pushes it.
- Feedback summaries (Summarize, one read-only `omp` call).

Personal filter preferences are stored per GitHub viewer in `hub.filters.<lowercase login>`:
`{ schema: 1, repositories?: string[], repositoriesEnabled: boolean, titleRules: TitleRule[], ignoredChecks: IgnoredCheck[] }`.
The plugin boundary is `Fetch.hubFilters(viewer)` / `Fetch.saveHubFilters(viewer, value)`; replace
these with viewer-scoped browser or server preferences. `hub/filter-store` owns loading/saving;
`hub/check-filter` owns on-demand named-check reads. Port both orchestration modules over these seams.

`GithubClient.refresh` accepts optional `checkNames: Record<string, boolean>` (lowercase repository
names). `GithubClient.checkNames(ids)` uses `docs/hub/queries/check-names.graphql` and returns the
same envelope as `checks(ids)`, with optional `Checks.failedNames: string[]`. Read up to 100 contexts
for each of at most 10 PRs per request. Partial or missing names never suppress unknown failures.
The checks snapshot's head must match before applying it; a replaced snapshot rejects an on-demand
answer. This feature adds opt-in GraphQL calls; the ordinary count-only refresh is unchanged.

`TitleRule` is `{ operator: 'contains' | 'not_contains' | 'starts' | 'not_starts', value: string, enabled: boolean }`.
`IgnoredCheck` is `{ repo: string, name: string, enabled: boolean }`. Pass ignored rules to model
placement/order/queue functions. They suppress only the Needs fixes checks reason, preserving
raw check counts, merge gates and shared-cache facts. Durable visibility filters narrow Next up;
search stays temporary. `State.saved` includes both rule types and repositoriesEnabled.

## How the code splits

Every module falls into one of two kinds. Pure modules hold the rules, read no clock, file or network, and have tests that run under plain `luau`. Host modules run commands, read the key/value store, set timers or draw. The refactor on branch `hub-seams` made that split clean.

- Port the pure modules 1:1, with their tests. They are most of the logic: `src/hub/model.luau`, `src/hub/state.luau`, `src/hub/sync.luau`, `src/github.luau`'s parsers, `src/keys.luau` and the rest that [the module map](#appendix-a-module-map) marks "port 1:1".
- Rewrite the host modules against the seams in [Appendix B](#appendix-b-the-seams-as-typescript). There are six seams: `Host`, the per-window `cx`, `GithubClient`, the prdata contract, the agent-host contract and the store.
- Rewrite the views (`src/view/*.luau`) as React components. They only turn state into nodes, so each is a function of `State`.

## Leave out Tandem

Tandem's code is isolated, but its flag on a PR reaches the shared rules. Remove all of the following. The board then behaves as the plugin does for a PR that Tandem does not watch.

Modules to skip whole:

- `src/tandem.luau` (`watch`, `handoff`, `clone`).
- `src/hub/tandem.luau` (`loadTandem`, `handoff`, and `projectRoot`).

Fields to drop:

- `HubPR.tandem` in `src/hub/model.luau`, and `tandem = isBool` in `PR_FIELDS` in `src/hub/sync.luau`. `Sync.load` rejects a cached PR without that field, so remove it from the check, not only from the type.
- `Local.tandem` in `src/hub/sync.luau`, and the line in `Sync.merge` that sets `pr.tandem` from it.
- In `Block` (`src/hub/runtime.luau`): `watched`, `handoffs`, `heard`, `retired`, `root`, `rootWaiters`, `flights.tandem`. Keep `seen`, `held` and `replays`, which the cache sync uses. The store sets `unsaved` on several paths, but only `src/hub/tandem.luau` reads it, so it goes with Tandem.

Rules and functions to drop:

- `src/hub/model.luau`: the first rule of `classify` (a PR with `pr.tandem` goes to In review), `parseTandemWatch`, `tandemFlags` and `handoffReason`.
- `src/hub/state.luau`: the `card-handoff` actions ("Hand off to Tandem"), the "Waiting on Tandem" chip, the `pr.tandem` branches in the card builders and `dropObsoleteAgents`'s watched-PR rule.
- `src/hub/store.luau`: `storedNow`, `joinOwnership`, `renewed`, `flagPrs`, `flagged`, `joinShared`, `joinOwned`, `applyOwnership`, `syncOwnership`, `ownershipChecked`, `reconcileFlight`, `UNCHECKED`, `TANDEM_OWNS`, the `answered` parameter of `reconcileStore` and `persistWhole`, and the `b.retired` check in `sharedCache`. `carryOn` keeps only its `currentFlight` check.
- `src/hub/ops.luau`: the `TANDEM_OWNS` and `ownershipChecked` guards in `runMerge`, `cancelMerge`, `autoMerge`, `updateBranch`, `pushEmpty` and `reviewEffect`, and the `syncOwnership` call inside `reviewEffect`'s `canPush`.
- `src/hub/refresh.luau`: the `loadTandem` call and the `joinOwnership`, `joinShared`, `applyOwnership`, `reconcileFlight` and `flagged` calls in `startRefresh` and `stepFixture`.
- `src/hub/agent-run.luau`: the `pr.tandem` guard in `beginAgent`, the `owner.tandem` cleanup branch in `retryAgent`, and the `carryOn` ownership half.
- `src/hub/block.luau`: `ACTIONS["card-handoff"]`, the `pr.tandem` guard in `ACTIONS["card-agent"]`, the `syncOwnership` call in `dispatch`, and the `watched` set and `raw-tandem-watch` fixture in `init`.
- `src/agent-host.luau`: the `tandem = Tandem.clone` entry in `findAgentClone`, and `CloneLookup.tandem` in `src/hub/agent-fix.luau`'s `locateClone`.
- `src/hub/runtime.luau`: the watched-card branch in `forgetReturned` that puts a failed state back.
- `src/view/hub/help.luau` and the README Keys table: the A and ⇧A wording that names Tandem.

Skip the Tandem scenarios of `tests/tandem_test.luau` (see [Appendix D](#appendix-d-tests)) and the fixtures `fixtures/hub/raw-tandem-watch.*` and `fixtures/hub/raw-tandem-pr-fix.*`.

The agent-fix worktree lease is not Tandem, but it uses Tandem's pool. `AgentHost.startAgentFix` leases a worktree with `treehouse` from `TANDEM_POOL_ROOT` or `~/.tandem/pool` (`AgentFix.acquire`, `AgentFix.returnLease`). The worker needs its own worktree pool. Keep the lease contract (`Engine.held`, `Engine.release`, the `Lease` record).

## Decide where git and the agent run

Five features have no GitHub API equivalent. Each needs a git checkout, and two need the `omp` agent process.

| Feature | What it runs today | Where |
|---|---|---|
| Agent fixes (conflicts and bot feedback) | `git reset/clean/fetch/switch/merge/add/diff/commit`, `omp -p`, `tools/conflicts`, `sandbox-exec` | `src/hub/agent-fix.luau` `engine` |
| Pushing a fix | `git ls-remote`, `git push https://github.com/<repo>.git <commit>:refs/heads/<branch>` | `AgentHost.pushAgentFix`, `ReviewFix.plan` |
| Merge-tree conflicts on the fixes page | `git merge-tree --write-tree --name-only`, `git show`, `git log -1` | `Prdata.readFixes` |
| Marking generated files on the guide page | `git check-attr --source=<head> -z --stdin linguist-generated` | `src/prdata.luau` `listChanges` |
| Saved clones | `git init --bare`, fetch into `refs/prguide/<n>/*`, `gh repo clone --filter=blob:none` | `Fetch.prepareCache`, `AgentFix.clone` |

AI guide generation and Summarize also need `omp`, but no checkout. Guide generation runs `omp -p` in the checkout today, so the agent can read files. It can run in the worker's checkout too.

This is an open decision. Choose one of two options.

**Option 1. A server-side worker with a checkout.** A job queue runs git and `omp` on a machine that keeps bare clones and leases worktrees. The pure engine (`AgentFix.engine`) and the plans (`ReviewFix.plan`, `ReviewFix.readCommands`) already take an injected runner, so they port 1:1 and run on the worker. `Prdata.readFixes` and the generated-file marking also run there. Costs:

- You run and secure a machine that executes an AI agent on untrusted repository code. Today a bot fix runs under macOS `sandbox-exec` with a profile from `AgentFix.sandboxProfile`. On Windows, which has no sandbox the plugin can apply, it runs unconfined (`Spec.unconfined`), with only its tools and prompt keeping it in the worktree. Linux needs a container or a seccomp equivalent.
- The worker pushes with a token that can write to the PR's head repository, forks included.
- Clones cost disk and the first fetch of a big repo is slow (`GIT_FETCH_MS` is 20 minutes).
- `tools/conflicts` (Python) must be on the worker.

**Option 2. Redesign the git parts on the Git Data API.** Read files with `GET /repos/{o}/{r}/contents/{path}?ref=`, trees with `GET /git/trees/{sha}` and blobs with `GET /git/blobs/{sha}`. Compute conflicts in TypeScript with a three-way merge library. Write a fix as blobs, a tree and a commit (`POST /git/blobs`, `/git/trees`, `/git/commits`), then move the branch with `PATCH /git/refs/heads/{branch}`, with `force: false`. Costs:

- No `omp` process on a checkout. The agent must work through tools you build over the API, or an agent runtime that holds the files in memory.
- No lockfile regeneration (`AgentFix.regeneration` runs `npm install --package-lock-only` and similar). A conflict in a lockfile becomes "resolve on GitHub".
- `git merge-tree` conflict markers and the "Main changed this in #415" cause (`git log`) have to be rebuilt from the compare API (`GET /compare/{base}...{head}`) and commit history.
- `.gitattributes` `linguist-generated` patterns must be read from the repo and matched in code.
- Every file read costs an API call, against a rate limit of 5,000 REST requests per hour per token.

Option 1 keeps every tested engine path. Option 2 removes the worker but rewrites the engine, which `tests/agent_fix_test.luau` pins. Start with option 1 unless running untrusted code is ruled out.

Saved clones and checkout discovery (`Fetch.findRepo`, `Fetch.checkoutFor`, `Fetch.savedCopy`, `Fetch.readySavedCopy`, `AgentHost.findAgentClone` with its folder prompt) exist because the plugin runs on the reviewer's machine. A hosted app has no reviewer checkout. Drop them, and let the worker own its clones.

## Run the tests first

The tests are the spec for every pure module. Run them before you change anything, and keep them passing in the plugin while you port.

```sh
/opt/homebrew/bin/luau tests/run.luau
```

It runs 20 test modules in a few seconds and prints `all 20 test module(s) passed`. A failed assert names its module and exits non-zero.

To port a module:

1. Port its test file to your TypeScript test runner first, assertion for assertion. Keep each assert's message.
2. Port the module until its tests pass.
3. Feed the same fixtures. `fixtures/hub/raw-*.json` are recorded GitHub answers. The `.luau` twins exist only because `luau` has no file I/O, and `tools/luau-fixtures` regenerates them, so read the JSON directly.

The GraphQL queries live twice, in `src/github.luau` and in `docs/hub/queries/*.graphql`. `tools/luau-fixtures --check` fails when they differ. In the port, load the `.graphql` files and delete the copies.

[Appendix D](#appendix-d-tests) maps each test file to what it pins. Some modules have no tests: `src/search.luau`, `src/lens.luau`, `src/text.luau` and `src/text-field.luau`. `tests/groups_test.luau` covers only the tests-and-generated-files part of `src/guide.luau`, `src/review.luau`, `src/state.luau`, `src/agent.luau`, `src/file-tree.luau` and `src/git-output.luau`. They are pure, so port them line by line and write tests from their behavior in the sample block (**New PR Guide sample block**, which opens `fixtures/pr-350.json` with `fixtures/guide-350.json`).

## Port in this order

1. **Pure models and state.** `hub/model`, `hub/sync`, `hub/fixes`, `hub/summary`, `hub/agent-fix`, `hub/review-fix`, `hub/state`, `links`, `keys`, then the guide page's `pr`, `diff`, `moves`, `file-group`, `guide`, `review`, `search`, `state`, `file-tree`, `lens`, `text`, `text-field` and `agent`, and `ci/log`. Port each with its tests. Remove Tandem as you go.
2. **The GitHub client.** Port `src/github.luau`'s parsers with `tests/github_test.luau`. Replace the `gh` transport with `fetch` against REST and GraphQL ([Appendix B.3](#b3-githubclient)). Then write `PrData` on the API ([Appendix B.4](#b4-prdata)), and the CI log readers on the Actions and Buildkite APIs ([B.3.1](#b31-ci-logs)).
3. **The store.** Port the shared cache (`hub/store`) on a server key/value store with a conditional write ([Appendix B.6](#b6-the-shared-cache-store)). Port the cache scenarios of `tests/tandem_test.luau` and `tests/summary_test.luau` as integration tests.
4. **The hub runtime.** Port `hub/refresh`, `hub/lookups`, `hub/details` and `hub/ops` over the client and the store, then the `ACTIONS` table ([Appendix C](#appendix-c-the-hub-runtime)).
5. **Views.** Rewrite `src/view/**` as React components over `State`, using `guide.css`'s `gp-` classes and the tokens in `DESIGN.md`. Check light and dark.
6. **The worker.** Agent fixes, push, merge-tree conflicts and guide generation, per the option you chose.

---

## Appendix A. Module map

Each module's one job comes from its header comment. A verdict says what the port does with it.

### The guide page

| Module | One job | Verdict | Tests |
|---|---|---|---|
| `src/review-page.luau` | The review page's runtime: opens the PR its arguments name (or the bundled sample), draws the page, and turns clicks and keys into state changes plus the scrolling, focusing and animation timing only a live window can do. A host mounts it at a node path, its `root`, which every frame op and view path starts with. | Rewrite for the web host. Keep its `ACTIONS` table as the page's action vocabulary. | none |
| `src/block.luau` | The `prguide.guide` block: a thin shell that mounts a review page at the `"main"` region. | Drop. | none |
| `src/state.luau` | What the page shows on top of the review itself, and the changes to it that need no window. `cardSites` lists the comment cards a block hangs and `runStarts` which run of lines each entry is drawn in (via `Diff.runStarts`), shared by the code view and the page's path helpers. | Port 1:1. | `diff_test` (`Diff.runStarts`) |
| `src/model-box.luau` | The model and lens menu's state and what its actions do to the agent's picks, shared by the review page's model menu and the hub's Settings. | Port 1:1. | `model_menu_test`, `hub_settings_test` |
| `src/review.luau` | The review: steps in reading order, decisions on suggestions, own comments, the verdict and the `Payload` for GitHub's create-review call. No header comment. | Port 1:1. | none |
| `src/guide.luau` | Parses and validates a guide file against a PR (`parse`, `read`, `defaultGuide`, `isStale`), and the review pass's file (`parseDraft`, `readDraft`, `withDraft`). No header comment. `read` uses `Host.fs`. | Port 1:1. Change with `GUIDE.md`, `prompts/explain.md` and `prompts/review.md`. | none |
| `src/diff.luau` | Diff analysis for one file: spans, commentable ranges, the layout with hidden runs, `runStarts` (the run of lines each entry draws in), tokens. No header comment. | Port 1:1. | `diff_test`, `moves_test` |
| `src/moves.luau` | Move detection: code the PR cut from one place and pasted in another, matched by whole runs of trimmed lines, so a block that only moved reads as moved. | Port 1:1. | `moves_test` |
| `src/file-group.luau` | Which changed files the page sets apart when no step visits them: tests, found by path, and generated files, which git's `linguist-generated` attribute marks. | Port 1:1. The port reads `linguist-generated` on the worker or from `.gitattributes` ([B.4](#b4-prdata)). | `groups_test` |
| `src/search.luau` | The `/` search over steps, suggestions, own comments and files. No header comment. | Port 1:1. | none |
| `src/pr.luau` | The `PR`, `File` and diff `Row` types, and `sample()`. No header comment. | Port 1:1. `sample` reads `fixtures/pr-350.json`. | through `diff_test`, `moves_test`, `groups_test` |
| `src/file-tree.luau` | Changed files as a folder tree, laid out the way GitHub lists them, with tests and generated files after the others, each as a tree of its own. | Port 1:1. | `groups_test` |
| `src/git-output.luau` | Turns the output of the git commands prdata.luau runs into the PR's files, each marked with its `FileGroup` group. | Replace with GitHub API (`GET /pulls/{n}/files` gives status and patch). Keep it only on the worker. | `groups_test` (the group marking) |
| `src/lens.luau` | Review lenses: what the AI reviewer pays attention to, parsed from markdown. | Port 1:1. The lens files are `lenses/*.md`. | none |
| `src/agent.luau` | The reader's own AI agent writing a guide: the model and effort of each pass (OMP's `smol` role explains until the reader picks a model), the models it can pick from, and the files a run reads (the numbered diff, with generated, vendored, minified and snapshot files as one line each and whitespace-only hunks counted). | Port 1:1. `workDir` and `CONFIG` name local paths the worker sets. | `agent_test`, `agent_diff_test` |
| `src/text.luau` | String helpers. No header comment. | Port 1:1. | none |
| `src/text-field.luau` | A text field's editing model (`Field`, `key`, cursor and selection). No header comment. | Port 1:1, or replace with native inputs. `keys.luau` reads its `Outcome`. | through `state_test`, `agent_state_test`, `review_fix_test` |
| `src/keys.luau` | What each key does in each mode, as the same actions the page's clicks send. | Port 1:1. | `agent_state_test`, `review_fix_test`, `summary_test` |
| `prompts/explain.md`, `prompts/review.md` | The prompts `omp` follows: the explanation (overview, flow, changes) and the review (comments, summary, through a lens). | Port 1:1 as text. Change with `GUIDE.md` and `src/guide.luau`. | none |

### The hub

| Module | One job | Verdict | Tests |
|---|---|---|---|
| `src/hub/model.luau` | The hub's rules: which column a PR is in, in what order, and what needs the viewer next. | Port 1:1 with its tests, minus the Tandem rule and parsers. | `model_test`, and via others |
| `src/hub/filter-store.luau` | Personal filter preferences by viewer. | Port with a viewer-scoped preference store. | `filter_test` |
| `src/hub/check-filter.luau` | Read named check failures on demand, rejecting stale answers. | Port with `GithubClient.checkNames`. | `filter_test` |
| `src/hub/state.luau` | The hub's interaction state (tab, selection, filter, sort, search, open menus) and the board built from it. | Port 1:1 with its tests, minus Tandem actions. | `state_test`, `selection_test`, `merge_test`, `rereview_test`, `flake_test`, `agent_state_test`, `review_fix_test` |
| `src/hub/sync.luau` | The pure sync decisions: the cache's shape, the merge-method record, the recent store, what changed between two refreshes, and when each poll is due. | Port 1:1 with its tests, minus `Local.tandem`. | `sync_test`, `merge_test` |
| `src/hub/fixes.luau` | What the fixes page shows: the details model, the noise filter, the steps, the code excerpts, and the readers of local git output. | Port 1:1 with its tests. The git readers (`parseMergeTree`) matter only with a worker. | `fixes_test` |
| `src/hub/checks.luau` | What the checks popover shows: the check list's shapes (`CheckRow`, `CheckList`, `Load`, `Popover`), the groups (Failing, Running, Queued, Passed behind a fold) as `lines`, each row's time, the card's checks mark, and a failing check running again. | Port 1:1 with its tests. | `checks_test` |
| `src/hub/summary.luau` | Feedback-only prompts, conservative summary parsing and the comments-only action rule. | Port 1:1 with its tests. | `summary_test` |
| `src/hub/agent-fix.luau` | The agent fix's pure transitions and injected effect pipeline. | Port 1:1 with its tests, on the worker. Drop `CloneLookup.tandem`. | `agent_fix_test`, `agent_state_test` |
| `src/hub/review-fix.luau` | Conflict-only excerpts from an immutable fix commit, and the plans that gate Push and Discard. | Port 1:1 with its tests. | `review_fix_test` |
| `src/hub/runtime.luau` | The hub block's runtime record (`Block`) and what every hub module does to the window through it: `draw`, `stop`, frame ops, arrival alerts, fixtures. | Rewrite for the web host. | via `tandem_test`, `summary_test` |
| `src/hub/store.luau` | The shared cache (`hub.cache`), write ids, edit replay, adoption, and the Tandem ownership guard. Also `hub.added` and `hub.status`. | Rewrite for the web host, minus Tandem. Keep the write-id and replay rules. | `tandem_test` (cache scenarios), `summary_test` |
| `src/hub/lookups.luau` | How each repo merges (`hub.merge.<owner>/<repo>`, else GitHub's answer) and flake evidence for a failing check. | Port the logic. Swap `Host.kv` for the store. | `merge_test`, `flake_test` (pure parts) |
| `src/hub/prepare.luau` | Background guides (Settings, off by default): after each refresh and once on start, review requests of the viewer whose saved guide is missing or for another head are explained one at a time, through the `hub.preparing` lease so two windows don't take the same PR. Explanation only. | Rewrite as a worker job queued after a refresh; the lease becomes a job lock. | `prepare_test` |
| `src/hub/refresh.luau` | The probe, refresh and checks timers armed from `Sync.schedule`, each answer laid onto the newest shared cache, `refetch`, the sample board's ⌘R, and `loadCheckList` (a PR's check list, read again on the checks timer while the popover is open and a check is unfinished). | Rewrite for the web host. Keep `Sync.schedule` as the only timing rule. | via `tandem_test` |
| `src/hub/details.luau` | Reading what a PR's pages show: feedback details, the fixes page's details, local git and failed-check logs (`readLogs`, through `b.ci`), the review fix page's files. | Rewrite for the web host. The log reads go to the server ([B.3.1](#b31-ci-logs)). | via `summary_test` |
| `src/hub/agent-run.luau` | An agent fix's flight: clone lookup (asking for a folder when there is none), refs, engine start, settle, stop, retry, open worktree. | Rewrite for the web host. The folder prompt (`osascript`) and `open` drop. The flight becomes a worker job. | via `tandem_test`, `summary_test` |
| `src/hub/ops.luau` | The actions that reach GitHub or the agent: merge, cancel, merge when ready, batches, re-request, Update branch, re-run, add and remove by link, reply, resolve, Summarize, push or discard a fix. | Rewrite for the web host, minus the Tandem guards. Keep the order of each action's checks. | via `tandem_test`, `summary_test` |
| `src/hub/pages.luau`, `src/hub/page-views.luau` | Hosts review pages in the hub's pane (open, show, back, the last 3 kept, never dropping a page with unsent work) and the pure view rules (`views`, `next`, `tabs`, `victims`). The page seam is `ReviewPage.init(cx, args, root, hosted)` with `State.Hosted = { fixes }`, plus `atRest`, `reading`, `views`, `current`, `setView`, `unsaved`, `startGuide`, `tabsPath`. | Rewrite for the web host: pages are components kept in a small LRU. Keep `page-views` as is. | `pages_test` |
| `src/hub/block.luau` | The PR hub block: reads its arguments, opens the board from the shared cache or a sample, draws it, and runs one `ACTIONS` table for clicks and keys. | Rewrite for the web host. Port the `ACTIONS` table as is. | via `tandem_test`, `summary_test` |
| `src/hub/tandem.luau` | The hub's side of Tandem: `loadTandem`, `handoff`. | Drop: Tandem. | `tandem_test` |

### CI logs

A failing check with no usable annotation shows its log on the fixes page, and Re-run failed checks re-runs it. Each CI is its own module that meets one contract, and `ciProviders` in `src/hub/block.luau` is the only place they meet.

| Module | One job | Verdict | Tests |
|---|---|---|---|
| `src/ci/log.luau` | The shape of a failed-check log (`Log`, `Section`, typed `Line`s, `Load`), `classify` and `line` (a raw line's level, its CI marker dropped), `errors`, the `Provider` contract (`owns`, `read`, `retry`), `providerFor`, `byProvider` (failing checks by the module that owns them), `each` (one call after another) and `refs` (the changed files a log names). Pure. | Port 1:1. | `ci_log_test` |
| `src/ci/actions.luau` | GitHub Actions logs: which checks are Actions jobs, the `gh run view --log-failed` command (`command`), the cut that keeps 12 lines before and 3 after each error, 120 a job at most (`parse`), and `gh run rerun --failed` once per run (`retryCommand`). | Port `jobId` and `parse` 1:1. Replace the commands with the Actions API ([B.3.1](#b31-ci-logs)). | `ci_log_test` |
| `src/ci/buildkite.luau` | Buildkite logs: which checks are Buildkite builds, the `bk build view`, `bk job log` and `bk job retry` commands, and the readers of their output. | Port `build`, `parseFailures` and `parseLog` 1:1. Replace `bk` with the Buildkite REST API ([B.3.1](#b31-ci-logs)). | `ci_log_test` |

### Boundaries and the host

| Module | One job | Verdict | Tests |
|---|---|---|---|
| `src/host.luau` | The platform calls every non-view module makes: processes, kv, files, JSON, timers, environment, clocks, the operating system, plugin folders. | Rewrite for the web host ([B.1](#b1-host)). | swapped in `summary_test`, `tandem_test`, `fold_test` |
| `src/platform.luau` | What differs by operating system: the home and temp folders, PATH splitting and program names (PATHEXT on Windows), the Python that runs `tools/conflicts`, and the command that opens a link or folder outside Tern. | Drop: the worker runs on one known OS, and the browser opens links in a new tab. | `platform_test` |
| `src/github.luau` | The hub's GitHub boundary. Every call goes through an injected `Runner` and JSON through an injected `decode`. Parsers never throw, and failures are `Error` values. | Replace with GitHub API for the transport. Port the queries, parsers and `historyCache` 1:1. | `github_test` (exact argv through `tests/fake-runner.luau`), `fixes_test`, `flake_test`, `merge_test`, `rereview_test`, `selection_test` |
| `src/prdata.luau` | Reading a PR and posting a review through `gh` and `git` in a checkout; what the fixes page reads for conflicts. | Replace with GitHub API ([B.4](#b4-prdata)). `readFixes` goes to the worker. | none |
| `src/agent-host.luau` | The reader's agent (`omp`) as a process: finding it, its models, writing a guide, summarizing feedback, and agent fixes. | Rewrite for the web host, as the worker's API ([B.5](#b5-the-agent-host)). | stubbed in `summary_test`, `tandem_test` |
| `src/fetch.luau` | The plugin's host side: command runners on the reader's shell PATH, checkouts and saved copies, guide and lens files, recent PRs, run durations and where links open (`linkTarget`, `saveLinkTarget`), and opening a link in the system browser (`openInBrowser`). | Rewrite for the web host. Shell PATH, checkouts and saved copies drop. `recentPrs`, `rememberPr` and run seconds move to the store. `linkTarget` and `openInBrowser` drop: a web app opens GitHub links in a new tab. | none directly |
| `src/tandem.luau` | Tandem through its CLI and database. | Drop: Tandem. | `tandem_test` |
| `src/links.luau` | Link and number parsing, the `#prguide-open=` link, which pane ⌥⌘R opens, and the status segment's text and timing. | Port the parsing 1:1 with its tests. `hubEntry` and the status watcher drop with the window. | `links_test` |
| `window.luau` | The window half: the commands, the status segment and the link route that opens a card's PR in the guide. | Rewrite for the web host: routes for the hub and the guide page, a badge or title count from `hub.status`. | none |
| `host.luau` (repo root) and `plugin.toml` | Tern's plugin manifest and block registration. | Drop. | none |

### Views and styles

| Module | One job | Verdict |
|---|---|---|
| `src/view/ui.luau` | Node builders every view shares (`Ui.el`, `Ui.span`, `Ui.field`). | Rewrite as React views. |
| `src/view/page.luau` | The page: header, description, overview, each change's card beside its code, supporting files, hint bar, the header and hint bar pinned around a scrolling body (`<root>.page.body`; without a guide the body does not scroll and the code column `<root>.page.body.ch1.code` does, `Page.scrollPath(s)`); the node paths the page scrolls to, each built from the page's `root`: `blockPath`, `topPath`, `stepPath`, `suggestionPath`, `composerPath`, and `linePath(s, blockId, entry)`, which names a diff line's node from `State.runStarts` (nothing the draw stored). | Rewrite as React views. |
| `src/view/header.luau` | The pinned header: title, review button, progress, actions, the open panel. | Rewrite as React views. |
| `src/view/description.luau` | The PR description as its author wrote it. | Rewrite as React views. |
| `src/view/overview.luau` | The PR in plain words, then how one run flows through the code. | Rewrite as React views. |
| `src/view/change.luau` | The left column beside one change. | Rewrite as React views. |
| `src/view/code.luau` | Code blocks: pinned file header, diff lines, gap bars, comment cards. | Rewrite as React views. |
| `src/view/comments.luau` | Comment cards under code lines. | Rewrite as React views. |
| `src/view/supporting.luau` | Changed files no step visits, as a folder tree. | Rewrite as React views. |
| `src/view/review-panel.luau` | The review as GitHub will receive it. | Rewrite as React views. |
| `src/view/search-panel.luau` | The `/` search box and its results. | Rewrite as React views. |
| `src/view/model-panel.luau` | The model and lens menu: its parts (`parts`), shown by the review page as its own overlay (`view`) and by the hub's Settings above the links toggle. | Rewrite as one React component used in both places. |
| `src/view/notice.luau` | The page while there is no review: loading stages or why it stopped. | Rewrite as React views. |
| `src/view/hints.luau`, `src/view/help.luau` | The hint bar and the `?` panel. | Rewrite as React views. |
| `src/view/hub/board.luau` | The hub page: header, tabs, columns, the Inactive fold, the hint bar. | Rewrite as React views. |
| `src/view/hub/card.luau` | One PR as a card. | Rewrite as React views. |
| `src/view/hub/fixes.luau` | The fixes page. | Rewrite as React views. |
| `src/view/hub/review-fix.luau` | The retained agent fix as review steps. | Rewrite as React views. |
| `src/view/hub/menus.luau`, `selection.luau`, `link.luau`, `help.luau`, `hints.luau`, `paths.luau` | Menus, the selection bar, the add-by-link box, the `?` panel, the hint bar, node ids for scroll and focus. | Rewrite as React views. |
| `src/view/hub/checks.luau` | The checks popover, the card's checks mark, and the popover's hint keys. | Rewrite as a React popover. |
| `guide.css` | Every style, `gp-` classes over Tern's tokens. | Reuse in the React views. `docs/tern-tokens.css` holds the token values. |

### Tools

| Tool | Job | Verdict |
|---|---|---|
| `tools/conflicts` | Python. Resolves one merge hunk at a time for the agent, with a journal in the worktree's git dir. | Keep on the worker (option 1). |
| `tools/luau-fixtures` | Writes the `.luau` twins of `fixtures/hub/*.json` and checks the queries match `docs/hub/queries`. | Drop. |
| `tools/hub-smoke` | Seeds a disposable repo with four PRs (clean, behind, conflicted, failing). | Keep for live end-to-end tests. |

---

## Appendix B. The seams as TypeScript

Luau callbacks become Promises. A Luau `done(value?, err?)` that never throws becomes a Promise that resolves to a result union, so the "failures are values" contract survives. `T?` becomes `T | undefined`. A table keyed by string becomes `Record<string, T>`.

```ts
type Result<T, E = string> = { ok: true; value: T } | { ok: false; error: E }
```

### B.1 Host

From `src/host.luau`. Only this module and `src/view/` read `tern`. Tests swap its fields.

```ts
interface ProcessOptions { cwd?: string; stdin?: string; timeout_ms?: number; env?: Record<string, string> }
interface ProcessResult { status: number; stdout: string; stderr: string; timed_out: boolean }
interface TimerHandle { cancel(): void }

interface Host {
	process: { run(argv: string[], opts?: ProcessOptions): Promise<ProcessResult> }
	kv: { get(key: string): Promise<unknown>; set(key: string, value: unknown): Promise<void> }
	fs: {
		read(path: string, maxBytes?: number): Promise<string>
		write(path: string, text: string): Promise<void>
		list(path: string): Promise<string[]>
		exists(path: string): Promise<boolean>
		mkdir(path: string): Promise<void>
		remove(path: string): Promise<void>
	}
	timer(ms: number, fn: () => void): TimerHandle
	getenv(name: string): string | undefined
	now(): number // monotonic milliseconds
	time(): number // wall-clock seconds since the epoch
	runtime: { os: string } // "macos", "linux", ...
	plugin: { data: string; dir: string }
}
```

| Field | Server | Browser |
|---|---|---|
| `process.run` | The worker's job runner (git, `omp`, `tools/conflicts`). | None. The browser calls the server. |
| `kv` | A database table or Redis, keyed per board ([B.6](#b6-the-shared-cache-store)). | None. Reads and writes go through the server. A per-tab UI state (`State.saved`) can use `localStorage`. |
| `fs` | The worker's disk: guides, prompts, lenses, journals. | None. |
| `json` | `JSON.parse` and `JSON.stringify`. `json.array` exists only to mark empty Luau tables as arrays. Drop it. | Same. |
| `timer` | `setTimeout` for server jobs. | `setTimeout` for polls, rings and frame ops. |
| `getenv` | Server config (`HOME` or Windows' `USERPROFILE`, `TEMP`, `PATH`, `PATHEXT`, `SystemRoot`, `TANDEM_POOL_ROOT` drop). | None. |
| `now` | `performance.now()`. | `performance.now()`. |
| `time` | `Date.now() / 1000`. | `Date.now() / 1000`. |
| `runtime.os` | Only `Platform` reads it: Windows changes the home and temp folders, PATH lookup, the Python name, the opener (`rundll32`, else `open` or `xdg-open`) and the bot fix's sandbox. Drop. | None. |
| `plugin.data`, `plugin.dir` | The worker's data folder and the app's install folder (for `tools/conflicts`, `prompts/`, `lenses/`). | None. |

Two calls read the clock outside `Host`. `Runtime.isoNow` formats `Host.time()` with `os.date`, and `Fetch.rememberPr` calls `os.date` with no time. Pass `now` in the port.

`kv.get` is synchronous in Tern, and the store's correctness depends on that. See [B.6](#b6-the-shared-cache-store).

### B.2 The per-window effects (`cx`)

A block receives `cx: BlockCx` in `init`, `event` and `key`. Non-view modules use six things on it. Every frame op is sent one timer tick after a render (`frameLater`), because its target must exist first.

```ts
type FrameOp =
	| ["focus", string] // node id
	| ["reveal", string, "start" | "nearest"] // scroll a node into view
	| ["scroll", string, string] // ["scroll", "main", how]

interface BlockCx {
	render(): void // throws when the window is gone; `Runtime.draw` catches that and stops the block
	toast(kind: "error" | "info" | "success", text: string, sub?: string): void
	open(url: string): void // a URL, or a folder path for Open worktree
	copy(text: string): void
	frame(ops: FrameOp[]): void
	cwd?: string // the folder the block was opened in
}
```

In React, `render` is a state update, `toast` is a toast library call, `open` is `window.open` or a router push, `copy` is `navigator.clipboard.writeText`, `frame` is `element.focus()` and `scrollIntoView({ block })`, and `cwd` drops. `render` throwing is how a closed block stops its timers (the private `stop` in `src/hub/runtime.luau`, which `Runtime.draw` calls). In React, clear timers in an effect's cleanup instead, and keep the `b.closed` checks as an unmounted flag.

The hub opens a PR in the guide by calling `cx.open` with `https://github.com/<owner>/<repo>/pull/<n>#prguide-open=<root>` (`State.openPlan`). `window.luau` routes that link to the guide block. In the web app, route to the guide page directly.

### B.3 GithubClient

From `Client` in `src/github.luau`. `Github.client(run, decode)` builds it over a `Runner`. In the port, build it over an HTTP client that holds the token. Each call returns its own `RateLimit`. A refresh sums several.

```ts
type Error = { operation: string; message: string; rateLimit?: RateLimit } // Model.Error
type RateLimit = { cost: number; remaining: number; limit: number; resetAt: string }
type PRRef = { repo: string; number: number }

type RefreshRequest = { added: PRRef[]; previous: HubPR[] }
type Refresh = {
	prs: HubPR[] // addedByMe false and pending unset; the caller fills them from local facts
	viewer: string
	rateLimit: RateLimit // the last call's
	calls: RateLimit[] // every call's, in order
	truncated: boolean // a search returned more than 50
	partial?: Error // threads or merge failures failed; prs still stand
	merged?: Opened[] // Recently merged, newest merge first (`at` is mergedAt); unset when that search failed
}
type Probe = { changed: boolean; lastModified?: string; pollSeconds?: number }
type ChecksUpdate = { byId: Record<string, { headOid: string; checks: Checks }>; rateLimit: RateLimit }
type Detected = {
	declared?: MergeMethod; learned?: MergeMethod
	viewerDefault: "squash" | "merge" | "rebase"; autoMergeAllowed: boolean
	checkedAt: string // "" here; the caller stamps it
}
type RunRow = { id: number; workflow: string; sha: string; conclusion: string }
type CheckState = "failing" | "running" | "queued" | "passed" | "skipped"
type CheckRow = { name: string; source?: string; state: CheckState; startedAt?: string; completedAt?: string; url: string }
type CheckList = { headOid: string; rows: CheckRow[] }
type RepoHistory = { base: string; byWorkflow: Record<string, { failed: number; total: number }> }

interface GithubClient {
	refresh(req: RefreshRequest): Promise<Result<Refresh, Error>>
	probe(since?: string): Promise<Result<Probe, Error>>
	checks(ids: string[]): Promise<Result<ChecksUpdate, Error>>
	details(pr: HubPR): Promise<Result<FixDetails, Error>>
	detect(repo: string): Promise<Result<Detected, Error>>
	history(repo: string, base: string): Promise<Result<RepoHistory, Error>>
	runs(repo: string, sha: string): Promise<Result<RunRow[], Error>>
	checkList(prId: string): Promise<Result<CheckList, Error>>
	run(command: GithubCommand): Promise<Result<string, Error>>
}
```

| Method | Today | Port |
|---|---|---|
| `refresh` | `gh api graphql` with `HUB_QUERY` (`docs/hub/queries/hub-f.graphql`), once per search in `SEARCHES` (`mine`, `requested`, `reviewed`), all three at once. Each search pages with `q`, `n` and `after`: 20 PRs a page (`PAGE_SIZE`) up to 50 (`SEARCH_MAX`), and a page that fails transiently is asked again at half the size, down to 5 (`PAGE_MIN`). The first page of `mine` carries one `added<N>: repository { pullRequest(number:) }` alias per PR in `req.added` (`hubQuery`). The first failure ends the refresh. Beside them, `MERGED_QUERY` (`merged.graphql`) with `q = MERGED_SEARCH` fills `merged` (`parseMerged`); its failure only leaves `merged` unset. Then `THREADS_QUERY` (`threads.graphql`) for PRs with unresolved threads whose activity changed, at most 100 ids (`threadsFor`). Then `MERGE_FAILURE_QUERY` (`merge-failure.graphql`) for PRs with a comment or label merge pending on the same head (`inFlightMerges`). | `POST /graphql`, the same queries and variables. Keep the paging, `pageInfo.hasNextPage` as `truncated`, and one `RateLimit` per page in `calls`. A threads or merge-failure failure sets `partial` and keeps `prs`. |
| `probe` | `gh api -i notifications?per_page=1`, with `-H If-Modified-Since: <since>`. `parseProbe` reads the status line. | `GET /notifications?per_page=1` with `If-Modified-Since`. 200 is a change, 304 is none. Keep `Last-Modified` and `X-Poll-Interval`. |
| `checks` | `gh api graphql` with `CHECKS_QUERY` (`checks.graphql`), `ids[]=` per node. Empty `ids` answers at once. | `POST /graphql`, same query. |
| `details` | `gh api graphql` with `DETAILS_QUERY` (`details.graphql`), `id=<node id>`, `head=refs/pull/<number>/head`. `parseDetails` reads `baseRef.compare(headRef: $head).behindBy` into `behindBy` (nil for null) and `headRefName` with `headRepository.nameWithOwner` into `branch` (nil when the fork is gone). | `POST /graphql`, same query and variables. |
| `checkList` | `gh api graphql` with `CHECK_LIST_QUERY` (`docs/hub/queries/check-list.graphql`, 1 point): every check on the head commit, `nodes(ids:)` on the PR's node id, parsed by `parseCheckList` (conclusions and statuses mapped to the five `CheckState`s). Read when the checks popover or the fixes page opens, and again on the checks timer while the popover is open and a check is unfinished. | `POST /graphql`, the same query. |
| `detect` | `gh api graphql` with `MERGE_DETECT_QUERY` (`merge-detect.graphql`), `owner`, `name`. | `POST /graphql`, same query. |
| `history` | `gh api repos/<repo>/actions/runs?branch=<base>&status=completed&per_page=100`. | `GET` the same path. One page. |
| `runs` | `gh api repos/<repo>/actions/runs?head_sha=<sha>&status=completed&per_page=50`. | `GET` the same path. One page. |
| `run` | Runs a `Github.commands` argv ([below](#githubcommand)). | One REST or GraphQL call per command kind. |

`Github.historyCache(client)` wraps `history` with a one-hour memory cache (`HISTORY_SECONDS = 3600`). Port it as is. `tests/flake_test.luau` pins it.

Every GraphQL read waits 30 seconds (`GRAPHQL_MS`), because GitHub stops a query at about 10 seconds and answers 502. A read that fails transiently (`transient`: our timeout, a 502, 503 or 504, or GitHub's "Something went wrong while executing your query") is run once more. Mutations are never retried.

`decoded` turns `gh` exit codes, rate-limit text and GraphQL `errors` into an `Error`. In the port, map HTTP status, `X-RateLimit-*` headers and GraphQL `errors` to the same `Error`. `operation` today reads like `"gh api graphql: hub"`. Pick new strings, but keep `"Couldn't …: reason"` messages, which `Runtime.reasonOf` splits.

#### GithubCommand

`Github.commands` builds an argv for each write. Replace it with a typed union, and keep each builder's branching.

```ts
type MergeMethod =
	| { kind: "squash" } | { kind: "merge" } | { kind: "rebase" }
	| { kind: "queue" }
	| { kind: "comment"; command: string; cancel?: string }
	| { kind: "label"; label: string }

type GithubCommand =
	| { kind: "merge"; pr: HubPR; method: MergeMethod }
	| { kind: "cancelMerge"; pr: HubPR; method: MergeMethod }
	| { kind: "autoMerge"; pr: HubPR; method: MergeMethod }
	| { kind: "requestReview"; pr: HubPR; logins: string[] }
	| { kind: "close"; pr: HubPR }
	| { kind: "refs"; pr: HubPR } // returns { headRefName, baseRefName, headRefOid }
	| { kind: "updateBranch"; pr: HubPR }
	| { kind: "headTree"; repo: string; oid: string } // returns the commit's tree sha
	| { kind: "emptyCommit"; repo: string; tree: string; parent: string } // returns the new commit's sha
	| { kind: "moveBranch"; repo: string; branch: string; sha: string }
	| { kind: "reply"; pr: HubPR; threadId: string; body: string }
	| { kind: "resolve"; threadId: string }
```

| Builder | Today | GitHub API |
|---|---|---|
| `merge` squash, merge, rebase | `gh pr merge N --repo R --squash` (or `--merge`, `--rebase`) | `PUT /repos/{o}/{r}/pulls/{n}/merge` with `merge_method`. Today there is no `sha` guard. Adding `sha: pr.headOid` is safer. |
| `merge` queue | `gh pr merge N --repo R --auto` | GraphQL `enqueuePullRequest` when the base branch has a merge queue, else `enablePullRequestAutoMerge`. `gh` chooses between them today, so the port must. |
| `merge` comment | `gh pr comment N --repo R --body <command>` | `POST /repos/{o}/{r}/issues/{n}/comments`. |
| `merge` label | `gh pr edit N --repo R --add-label <label>` | `POST /repos/{o}/{r}/issues/{n}/labels` with `{ labels: [label] }`. |
| `cancelMerge` queue | `gh pr merge N --repo R --disable-auto` | GraphQL `disablePullRequestAutoMerge`. A queued PR also needs `dequeuePullRequest`. |
| `cancelMerge` comment with `cancel` | `gh pr comment ... --body <cancel>` | `POST .../issues/{n}/comments`. |
| `cancelMerge` label | `gh pr edit ... --remove-label <label>` | `DELETE /repos/{o}/{r}/issues/{n}/labels/{name}`. |
| `cancelMerge` other kinds | Raises. | Keep it an error. |
| `autoMerge` squash, merge, rebase | `gh pr merge N --repo R --auto --squash` (or the method) | GraphQL `enablePullRequestAutoMerge` with `mergeMethod`. |
| `autoMerge` other kinds | Same as `merge`. | Same as `merge`. |
| `requestReview` | `gh pr edit N --repo R --add-reviewer a,b` | `POST /repos/{o}/{r}/pulls/{n}/requested_reviewers` with `{ reviewers }`. |
| `close` | `gh pr close N --repo R` | `PATCH /repos/{o}/{r}/pulls/{n}` with `{ state: "closed" }`. |
| `refs` | `gh pr view N --repo R --json headRefName,baseRefName,headRefOid` | `GET /repos/{o}/{r}/pulls/{n}`: `head.ref`, `base.ref`, `head.sha`. `hub/agent-run` reads it just before an engine starts and refuses when the head or base moved. |
| `updateBranch` | `gh pr update-branch N --repo R` | `PUT /repos/{o}/{r}/pulls/{n}/update-branch` (a merge, not a rebase). |
| `headTree` | `gh api repos/R/git/commits/OID --jq .tree.sha` | `GET /repos/{o}/{r}/git/commits/{sha}`: `tree.sha`. R is the head repository, a fork's for a fork PR. |
| `emptyCommit` | `gh api repos/R/git/commits -X POST -f message=… -f tree=T -f parents[]=OID --jq .sha` | `POST /repos/{o}/{r}/git/commits`: `sha`. |
| `moveBranch` | `gh api repos/R/git/refs/heads/B -X PATCH -f sha=S -F force=false` | `PATCH /repos/{o}/{r}/git/refs/heads/{branch}` with `force: false`, so only a fast-forward lands; a moved branch answers 422 "Update is not a fast forward". |
| `reply` | `gh api graphql` with `REPLY_MUTATION` | GraphQL `addPullRequestReviewThreadReply`, unchanged. |
| `resolve` | `gh api graphql` with `RESOLVE_MUTATION` | GraphQL `resolveReviewThread`, unchanged. |

`tests/github_test.luau` asserts the exact argv of each builder. Port those asserts as asserts on the request (method, path, body).

### B.3.1 CI logs

From `Provider` in `src/ci/log.luau`. `hub/details.luau` asks the first provider in `b.ci` that `owns` a failing check to `read` its log, once per check URL and commit. `hub/ops.luau`'s `rerun` reads the card's failing checks from the details, splits them with `Log.byProvider`, and calls each provider's `retry` once with all of its checks; a check no provider owns is named in the failure toast. The plugin builds `b.ci` over `Fetch.runner` (`ciProviders`); the sample board builds it over `fixtures/hub/ci-logs.luau`.

```ts
type Check = { name: string; url: string; runId?: number }
type Level = "error" | "heading" | "command" | "plain"
type Line = { kind: "text"; text: string; level: Level } | { kind: "gap"; count: number }
type Section = { title: string; lines: Line[] }
type Log = { sections: Section[] }
type Load = { state: "loading" } | { state: "loaded"; log: Log } | { state: "failed"; reason: string }
interface Provider {
	owns(check: Check): boolean
	read(check: Check, repo: string): Promise<Result<Log>>
	// Every failing check this provider owns, at once, so it re-runs each run or build once. Resolves to how many it started.
	retry(checks: Check[], repo: string): Promise<Result<number>>
}
```

| Call | Today | API |
|---|---|---|
| Actions log | `gh run view <runId> --repo R --log-failed [--job <job>]`, 60 s (`Actions.command`). The job comes from the check's link. `Actions.parse` keeps 12 lines before and 3 after each error line, the last 30 when none reads as one, and 120 a job at most. | `GET /repos/{o}/{r}/actions/runs/{run_id}/jobs` for the failed jobs and their steps, then `GET /repos/{o}/{r}/actions/jobs/{job_id}/logs` (a redirect to the plain-text log). That log is the whole job, so cut it to the failed steps before `Actions.parse`. |
| Buildkite failed jobs | `bk build view <org>/<pipeline>/<n> --recursive --json`, 60 s, with `BUILDKITE_ORGANIZATION_SLUG=<org>` so `bk` uses that org's saved token (`Buildkite.failuresCommand`). | `GET https://api.buildkite.com/v2/organizations/{org}/pipelines/{pipeline}/builds/{number}` with a Buildkite API token, then its failed `jobs`. |
| Buildkite job log | `bk job log <job> --agent --max-tokens 1500` for the first 3 failed jobs, or the one the link names (`Buildkite.logCommand`). `--agent` already keeps the lines around the errors. | `GET .../builds/{number}/jobs/{job_id}/log`. That is the whole log, so cut it as `Actions.parse` does. |
| Actions re-run | `gh run rerun <runId> --failed --repo R`, once per workflow run (`Actions.retryCommand`). | `POST /repos/{o}/{r}/actions/runs/{id}/rerun-failed-jobs`. |
| Buildkite re-run | `bk job retry <job>` with `BUILDKITE_ORGANIZATION_SLUG=<org>`, for the job a link names, else for each failed job of the build (`Buildkite.retryCommand`). | `PUT .../builds/{number}/jobs/{job_id}/retry`. |

`Log.refs` finds `path:line` mentions of the PR's changed files in a log (at most 5), and `hub/details.luau`'s `readLogFiles` reads those files with `Prdata.readFixes`, so the page can pin the lines like annotations. In the port those reads are contents API calls or worker reads, as for annotated files.

### B.4 PrData

From `src/prdata.luau`. The guide page calls `openPr` and `submitReview`. The hub's fixes page calls `readFixes`. Each calls `done` once, and the first failure ends the chain with a message naming the step.

```ts
// Today: a PR string (number, URL or branch), a checkout root, and the slug of a saved copy.
// The port names the PR by repo and number.
type Target = { repo: string; number: number }
type Destination = { repo?: string; dryRunPath?: string } // no repo: the bundled sample, nothing to post

type ReviewPayload = {
	commit_id: string; body: string; event: string // "COMMENT" | "APPROVE" | "REQUEST_CHANGES"
	comments: { path: string; line: number; side: string; start_line?: number; start_side?: string; body: string }[]
}
type Delivery = { kind: "posted"; url: string } | { kind: "saved"; path: string }

type FixRead = {
	mergeTree?: string // `git merge-tree --write-tree --name-only` output; unset when the PR has no conflict
	shown: Record<string, string> // each conflicted file with markers, at most 8
	logs: Record<string, string> // `%H\t%an\t%s` of the last base commit touching it
	files: Record<string, string> // annotated files at the head, at most 6
}

interface PrData {
	openPr(target: Target, progress: (stage: string) => void): Promise<Result<PR>>
	readFixes(pr: HubPR, paths: string[]): Promise<Result<FixRead>> // worker only
	submitReview(pr: PR, payload: ReviewPayload, to: Destination): Promise<Result<Delivery>>
	dryRunPath(number: number): string // "<temp>/prguide-review-<n>.json" today: /tmp, or %TEMP% on Windows
}
```

| Step | Today | GitHub API |
|---|---|---|
| `openPr` metadata | `gh pr view <pr> --json number,title,body,url,author,createdAt,baseRefName,headRefOid,mergeCommit` | `GET /repos/{o}/{r}/pulls/{n}`. `author` is `user.login`, `createdAt` is `created_at`, `baseRefName` is `base.ref`, `headRefOid` is `head.sha`, `mergeCommit` is `merge_commit_sha` when merged. |
| `openPr` refs and merge base | `git fetch` into `refs/prguide/<n>/*`, `git rev-parse`, `git merge-base` | `GET /repos/{o}/{r}/compare/{base}...{head}` gives `merge_base_commit`. A merged PR's exact parent needs git. |
| `openPr` changes and patches | `git diff --name-status`, `git diff -- <paths>`, `git check-attr ... linguist-generated` | `GET /repos/{o}/{r}/pulls/{n}/files` (status, renames, `patch`; paginated, 3,000-file cap). Read `.gitattributes` and match `linguist-generated` in code, or on the worker. Generated files stay, marked `generated`: the page lists them apart (`FileGroup`) and the guide agent sees each as one line. Lockfiles are left out (`GitOutput`). |
| `openPr` file contents | `git ls-tree`, `git cat-file --batch` at the head | `GET /repos/{o}/{r}/contents/{path}?ref={head}` or `GET /git/blobs/{sha}`. |
| `submitReview` head check | `gh pr view <url> --json headRefOid`. A different head refuses with "The PR moved on to … since this page loaded". | `GET /repos/{o}/{r}/pulls/{n}`, same check. |
| `submitReview` post | `gh api --method POST repos/<repo>/pulls/<n>/reviews --input -`, reading `html_url`. | `POST /repos/{o}/{r}/pulls/{n}/reviews` with the same payload. |
| `submitReview` dry run | Writes the payload to `dryRunPath`. | Keep a dry-run mode. Tests and `post=false` use it. |
| `readFixes` | `git merge-tree`, `git show <tree>:<path>`, `git log -1 --format=%H%x09%an%x09%s <mergeBase>..<base> -- <path>`, `git show <head>:<path>` | No API for merge-tree. Worker only, or rebuild per option 2. The annotated `files` can come from the contents API. |

`openPr` reports these stages through `progress`: "Reading the PR from GitHub", a fetch stage, "Reading the changes" and "Reading the changed files". `src/view/notice.luau` lists them. Keep stage strings that match the work the port does.

### B.5 The agent host

From `src/agent-host.luau`. Every function runs `omp`, `git` or `treehouse` on the reader's machine today. In the port these are the worker's API. Types come from `src/agent.luau` and `src/hub/agent-fix.luau`.

```ts
type AgentModel = { selector: string; name: string; efforts: string[] }
type AgentChoice = { model: string; effort?: string }
// model and effort are the review model, which agent fixes and the feedback summary also run with
type Agent = { command: string; path: string; model: string; effort?: string; explain: AgentChoice; review: boolean; models: AgentModel[]; lenses: Lens[]; lens: string }

type AgentFixRequest = {
	key: string; clone: string; checkout: string; branch: string; base: string; headOid: string
	number: number; regenerate?: Record<string, string[]>; input?: AgentFixInput
}
type AgentFixInput = { kind: "bot"; details: FixDetails; authors?: string[] }
type AgentFix = {
	worktree: string; branch: string; base: string; headOid: string
	commit: string; hunks: ConflictHunk[]; summary: string; usedAgent: boolean
}
type AgentOutcome =
	| { kind: "running"; run: AgentRun } | { kind: "ready"; fix: AgentFix }
	| { kind: "failed"; reason: string; worktree?: string } | { kind: "stopped" }
type Lease = { path: string; id: string; holder: string }
interface AgentEngine {
	stop(): void
	release(): Promise<Result<true>> // called only after Push or a confirmed Discard; never pushes
	begin(): void
	held(): Lease | undefined
	busy(): boolean
}
type AgentFixRead = { files: Record<string, string>; diff: string; originals?: Record<string, ReviewFixOriginal> }

interface AgentHost {
	findAgent(): Promise<Result<Agent>> // `omp` on PATH and the model from kv "model" or ~/.omp/agent/config.yml
	saveChoice(agent: Agent): void // kv "model": { model, effort, lens, explainModel, explainEffort }
	refreshChoice(agent: Agent): void // takes up kv "model" again: the review page or the hub's Settings may have saved since
	listModels(agent: Agent): Promise<AgentModel[]> // `omp models --json`; [] on failure
	explain(agent: Agent, repo: Repo, pr: PR): Promise<Result<Guide>> // prompts/explain.md with the PR description, one request: `omp -p --no-session --no-skills --no-rules --no-extensions --no-title --tools=read,grep,bash --model M [--thinking E] @prompt @diff "Follow the attached instructions exactly."`; the reply (bare or in a ```json fence) is written to <n>.json and read with Guide.read
	draftReview(agent: Agent, repo: Repo, pr: PR): Promise<Result<GuideDraft>> // prompts/review.md with the review model and lens, writes <n>.review.json; started on its own (`draft-review`), alongside an explanation or not
	summarizeFeedback(agent: { command: string; model: string; effort?: string }, prompt: string): Promise<Result<string>> // `Summary.plan` argv only
	startAgentFix(request: AgentFixRequest, agent: Agent, now: number, changed: (o: AgentOutcome) => void): { engine?: AgentEngine; done: Promise<Result<AgentFix>> }
	returnAgentFix(path: string): Promise<Result<true>>
	readAgentFix(fix: AgentFix): Promise<Result<AgentFixRead>>
	pushAgentFix(plan: ReviewFixPlan, canPush: () => boolean): Promise<Result<true>>
	// Plugin only: agentClones, rememberAgentClone, findAgentClone (kv "hub.clones", the folder prompt).
}
```

`startAgentFix` holds one engine at a time (`activeAgentFix`) and refuses a second ("An agent fix already holds a worktree"). `changed` streams outcomes while `done` settles once. In a web app, run the engine as a worker job and stream `AgentOutcome` to the browser over server-sent events or a WebSocket.

`pushAgentFix` checks the plan again, reads the PR (`gh pr view N --repo R --json headRefName,headRefOid,headRepository,headRepositoryOwner`, which is `GET /pulls/{n}`: `head.ref`, `head.sha`, `head.repo.full_name`), refuses when the head moved, then runs `git ls-remote` so a push whose answer was lost is never sent twice, then `git push`. It calls `canPush()` before every command. Keep all three checks.

`hub/agent-run.luau` reads the PR's refs before an engine starts with `Github.commands.refs` (see B.3). It runs that command through `Fetch.runner` directly, because it needs the raw JSON rather than the client's error mapping. In the port it is the same `GithubClient` call.

### B.6 The shared cache store

The store is the `Host.kv` keys the plugin writes. Every window of a Tern session reads and writes one store. In the web app, one board's store is shared by every tab of that board, so the same rules apply.

| Key | Value | Written by | Cap |
|---|---|---|---|
| `hub.cache` | `StoredCache` | `Store.persist` | 1 MiB, oldest `lastActivityAt` evicted first (`Sync.save`) |
| `hub.status` | `{ refreshedAt, counts: { toReview, needFixes, flashAt? } }` | `Store.writeStatus`, on every `hub.cache` write | a few bytes |
| `hub.added` | `Added` | `Store.writeAdded` | 50 (`State.ADDED_CAP`) |
| `hub.merge.<owner>/<repo>` | `MergeRecord` | `Lookups.saveRecord` | one per repo |
| `hub.recent` | `Opened[]` | `Fetch.rememberPr`, `Fetch.migrateRecent` | 8 (`Sync.RECENT_CAP`) |
| `hub.clones` | `Record<slug, path>` | `AgentHost.rememberAgentClone` | Plugin only. Drop. |
| `model` | `{ model, effort?, lens, explainModel?, explainEffort? }`: `model` and `effort` are the review model, which agent fixes also use; `explainModel` is kept only once the reader picks one, and until then OMP's `smol` role explains. A `review` switch older versions wrote is ignored on read and dropped on the next save | `AgentHost.saveChoice` (the review page's model menu and the hub's Settings), read again by `AgentHost.refreshChoice` when either opens | one |
| `runSeconds` | number: the last explanation's seconds | `Fetch.saveSeconds("explain")` | one |
| `reviewSeconds` | number: the last review's seconds | `Fetch.saveSeconds("review")` | one |
| `links` | `"tern" \| "browser"`: where GitHub links open | `Fetch.saveLinkTarget` (Settings, `hub-links`) | one. Drop: a web app opens links in a new tab. |
| `hub.prepare` | boolean: prepare AI guides for review requests in the background; missing means off | `Fetch.savePrepareGuides` (Settings, `hub-guides`) | one |
| `hub.preparing` | `{ key: "owner/repo#n@<head>", at: seconds }`: the PR a window is preparing a guide for; another window passes that PR by until it is returned or 20 minutes old | `Prepare` (`src/hub/prepare.luau`) | one |
| `recent` | legacy list, deleted by `Fetch.migrateRecent` | none | Drop. |

```ts
type Counts = { toReview: number; needFixes: number; flashAt?: number } // flashAt in seconds
type Cache = {
	schema: 1
	refreshedAt: string; viewer: string
	prs: HubPR[]
	rateLimit?: RateLimit
	lastModified?: string // the probe's validator
	counts: Counts
	merged?: Opened[] // the last Recently merged list; a refresh without one keeps it
}
// What `persist` stores: the Cache plus two fields the Sync.Cache type does not declare.
type StoredCache = Cache & {
	writeId: string // "<window nonce>#<count>"; a cache stored before ids existed has none and reads as ""
	sinceAt?: number // seconds; when this cache's PR data was requested from GitHub (set in Refresh)
}
type Added = Record<string, PRRef> // by PR key
type Local = { added: Added } // `tandem` dropped
type MergeRecord = {
	schema: number; user?: MergeMethod; declared?: MergeMethod; learned?: MergeMethod
	learnedAnswered: boolean; checkedAt?: string
	viewerDefault?: string // "squash" | "merge" | "rebase"
}
type Opened = { repo: string; number: number; title: string; author: string; at: string }

// Runtime.Replay: a local edit no write has stored yet.
type Replay = {
	key: string; head: string; at: number; edit: () => void
	applied: boolean; present: boolean; queued?: boolean
}
```

`Sync.load` validates a stored value field by field and returns `undefined` for anything malformed, so a bad write never crashes a reader. Keep that at the store's read boundary.

The rules, all in `src/hub/store.luau`:

- **Write ids.** Every write carries a `writeId` no other write has (`WINDOW .. "#" .. writes`). A block remembers the id of the cache its board is (`b.held`) and every id it has stored or joined (`b.seen`).
- **Adopt the newer cache.** Before a write, the block reads the store. A stored cache with a strictly newer `refreshedAt`, or the same `refreshedAt` and an id this block does not hold, is another window's word. The block installs it whole first (`sharedCache`, `adoptShared`, `installShared`).
- **Replay local edits.** A local edit (a pending merge, a removed PR) that no write has stored is kept as a `Replay` and applied again to an adopted board, only while its PR is on the head it was made on (`keepCache`, `replayEdits`). `persist` drops the replays its write holds. A snapshot whose `sinceAt` is later than the edit and shows a new head drops the edit. A queue merge GitHub reports as removed retires its replay.
- **Read, then write, with nothing between.** `persistWhole` reads the store, installs a newer cache if there is one, re-applies the replays, and writes. In Tern nothing can run between that read and that write, because `kv.get` is synchronous and Luau is single-threaded. An async store breaks that. In the port, make the write conditional: compare the stored `writeId` with the one you read and retry the adopt-and-write on a mismatch. A database transaction or Redis `WATCH` gives you this.
- **An unreadable store writes nothing.** `readCache` returns `readable = false` when `kv.get` throws, and `keepCache` then reconciles without writing over a cache it could not see.

`tests/tandem_test.luau` pins these rules through its non-Tandem scenarios, and `tests/sync_test.luau` pins `Sync.load`, `Sync.save` and `Sync.merge`.

---

## Appendix C. The hub runtime

### The Block record

`Block` in `src/hub/runtime.luau` is one hub window's state. `State` (`src/hub/state.luau`) is everything the view reads. `Block` holds the rest.

| Field | Meaning | Port |
|---|---|---|
| `s` | The hub's `State`. | Keep. |
| `cache` | What `hub.cache` last held, or this block last wrote. | Keep. |
| `fixture` | `fixture=<name>`: recorded data, no network, no timers. | Keep for a demo board and for tests. |
| `generate` | ⏎ opens the PR with the AI guide started. | Keep. |
| `agent` | The reader's agent, once found. | Keep, from the worker. |
| `agentFlight` | The agent fix's lookup, engine and retained lease. | Keep, as the worker job's handle. |
| `botKeys` | Which cards' fix is a bot fix, across stop and retry. | Keep. |
| `github` | The `GithubClient`. | Keep. |
| `timers` | `probe`, `refresh`, `checks`, `debounce`, `ring` handles. | Keep. |
| `ci` | Who reads a failing check's log and re-runs it: Buildkite, then GitHub Actions (`ciProviders`). | Keep, as server calls ([B.3.1](#b31-ci-logs)). |
| `flights` | One call of each kind at a time: `refresh`, `checks`, `probe`, `flake`, `tandem`. | Keep, minus `tandem`. |
| `watched` | The PRs Tandem watches. | Drop: Tandem. |
| `handoffs` | Hand-offs Tandem took this session. | Drop: Tandem. |
| `seen` | Write ids this block stored or joined. | Keep. |
| `heard` | Ownership-bearing writes heard since the read of Tandem began. | Drop: Tandem. |
| `held` | The write id of the cache this block's board is. | Keep. |
| `replays` | Local edits no write has stored. | Keep. |
| `retired` | Write ids a successful read of Tandem superseded. | Drop: Tandem. |
| `unsaved` | Ownership restored onto an adopted cache that no write has stored. Only `src/hub/tandem.luau` reads it. | Drop with Tandem. |
| `root`, `rootWaiters` | The repository root of `cx.cwd`, for Tandem's calls. | Drop: Tandem. |
| `sched` | What `Sync.schedule` reads between ticks: `probedAt`, `probeChanged`, `focusedAt`, `checksAt`, `refreshTried`, `lastModified`. | Keep. |
| `closed` | The window is gone. | Keep, as an unmounted flag. |
| `refetch` | A refresh was asked for while one ran. | Keep. |
| `show` | A PR just added by link, to select when the refresh brings it. | Keep. |
| `records` | Each repo's `hub.merge.*` record, read once. | Keep. |
| `detecting` | Repos whose merge method was asked for this session. | Keep. |
| `histories` | `Github.historyCache`. | Keep. |
| `flakeTried` | Cards (by key and head) whose flake evidence was read. | Keep. |
| `step` | Fixture only: how many recorded refreshes ⌘R has applied. | Keep for the demo board. |

### The ACTIONS table

Clicks and keys share one vocabulary. A click sends `{ act, value }` from the node (`actionOf`). A key goes through `Keys.hubAction(state, key)`, which returns the same `{ act, value }`. `dispatch` looks the name up in `ACTIONS` and calls the handler with `(b, cx, value)`. A ⌘-click or ⇧-click on a card turns `hub-open` into `hub-mark`.

Port the table as is, as a `Record<string, (b, cx, value) => void>` and one `dispatch`. A new control is one entry that a click and a key both send (AGENTS.md "Keyboard first").

| Action | Calls |
|---|---|
| `hub-focused` | Sent by the window on focus. `State.setRecent`, sets `sched.focusedAt`, `Refresh.rearm`. |
| `set-generate` | Sent by the window. Sets `b.generate`. |
| `hub-select` | `State.select` |
| `hub-open`, `open` | `openCard` → `openRow`: `Pages.open` (`Pages.plan`: `Fetch.checkoutFor`, `State.openPlan`; then `Links.openRoute`/`routeArgs` into `ReviewPage.init` under the hub's `main` root, kept in `Block.pages`, 3 at most), or `Details.openFixes` for a Needs fixes card (details, local git, CI logs), or `Details.openReviewFix` for a ready agent fix |
| `hub-open-generate` | `openRow(..., true)` |
| `hub-open-pane` | `openRow(..., false, true)`: `openPr`, the PR in a pane of its own (`cx.open`); ⌘⏎ on the board |
| `pages-cycle`, `pages-view`, `pages-back` | `hub/pages`: `t` cycles a PR's views (`PageViews.next`), a tab shows one (`fixes`, `guided`, `files`, `review`), Esc at the review page's rest returns to the board. Keys: `Keys.hubPageAction` on a shown page, `T` in `fixesKey`; the fixes tab strip's select events (`Paths.fixesTabs`) and the page's Fixes tab (`ReviewPage.tabsPath`) send `pages-view` |
| `hub-move` | `State.move`. On the top row (`State.onTopRow`) the board scrolls to its start (`Paths.body`), else `Runtime.revealSelected` |
| `hub-tab` | `State.setTab` or `State.switchTab` |
| `hub-next` | `State.walk`, then `revealSelected` |
| `hub-fold` | `State.toggleFold`. Opening a fold reveals its header at the top (`Paths.foldHead`) |
| `hub-escape` | `State.clearMarks`, else `State.setSearch(s, "")`, else `State.select(s, nil)` |
| `hub-search` | `State.openSearch`, focus `Paths.searchField` |
| `hub-searched` | `State.searched` |
| `hub-search-done` | `State.closeSearch(s, false)` |
| `hub-search-clear` | `State.closeSearch(s, true)` |
| `hub-menu` | `State.openMenu`, or `closeMenu` when it is open. Settings first takes up the saved choice (`AgentHost.refreshChoice`, live boards) and the lenses (`Fetch.refreshLenses`), then focuses `Paths.settingsField` |
| `hub-actions` | `State.select`, then `State.openMenu(s, "actions")` or `"merge"` |
| `hub-menu-move` | `State.menuMove` |
| `hub-menu-close` | `closeMenu` |
| `hub-menu-pick`, `hub-menu-select` | `pickRow`, which runs the row's own action, or `chooseMergeRow` (`Lookups.setUserMethod`, `State.beginMethodEdit`) |
| `hub-menu-enter` | `pickRow`, except in the repository list, where it returns to Filter |
| `hub-filter-toggle` | `State.toggleFilter`: pause a saved rule, keeping its values; persist personal preferences |
| `hub-filter-back` | `State.openMenu(s, "filters")`: cancel the draft |
| `hub-filter-focus` | Switch filter text editing on or off; focus `Paths.filterField` when typing |
| `hub-filter-save` | `State.saveFilter`, `FilterStore.save`, `CheckFilter.read` |
| `models-slot`, `models-filter`, `models-move`, `models-top`, `models-effort`, `models-pick`, `model-row`, `model-effort` | Settings' model and lens menu: `ModelBox.act` on `s.agent`, the same as the review page's entries; `AgentHost.saveChoice` when it says to save (never on a sample board), `State.closeMenu` when it says to close |
| `edit-lenses` | `Fetch.prepareLensFolder`, closes Settings and opens the folder |
| `hub-links` | `State.setLinks`, `Fetch.saveLinkTarget`: where GitHub links open (Settings) |
| `hub-guides` | `State.setPrepareGuides`, `Fetch.savePrepareGuides`, then `Prepare.run`: whether AI guides are prepared in the background (Settings) |
| `hub-help`, `hub-help-close` | `State.openHelp`, `State.closeHelp` |
| `card-agent` | `AgentRun.beginAgent(b, cx, key, "fix")` |
| `card-agent-clone` | `AgentRun.beginAgent(..., "clone")` |
| `card-agent-folder` | `AgentRun.beginAgent(..., "folder")` |
| `card-agent-stop` | `AgentRun.stopAgent` |
| `card-agent-retry` | `AgentRun.retryAgent` |
| `card-agent-worktree` | `AgentRun.openWorktree` |
| `card-summarize` | `Ops.summarize` |
| `card-method` | `State.openMenu(s, "merge")` |
| `hub-refresh` | `Refresh.refetch`, or `AgentRun.advanceAgentFixture` or `Refresh.stepFixture` on a sample board |
| `card-handoff` | `HubTandem.handoff`. Drop: Tandem. |
| `card-copy` | `cx.copy(title .. " " .. url)`, toast "Copied link" |
| `card-merge` | `Ops.mergeCard` |
| `card-cancel` | `Ops.cancelMerge` |
| `card-auto` | `Ops.autoMerge` |
| `card-rerequest` | `Ops.rerequest` |
| `hub-method-save` | `State.methodOfEdit`, `Lookups.setUserMethod` |
| `hub-method-cancel` | `State.cancelMethodEdit` |
| `hub-mark` | `State.toggleMark` |
| `hub-mark-stale` | `State.markStale` |
| `hub-marks-clear` | `State.clearMarks` |
| `hub-batch-merge` | `Lookups.detectRepo` for repos with no known method, then `State.askBatch(s, "ready")` |
| `hub-batch-close` | `State.askBatch(s, "inactive")` |
| `hub-confirm` | `Ops.confirm` (runs the batch one PR at a time) |
| `hub-confirm-cancel` | `Ops.confirmCancel` |
| `card-update` | `Ops.updateBranch` |
| `card-rerun` | `Ops.rerun` |
| `hub-link` | `State.openLink`, focus `Paths.linkField` |
| `hub-link-clear` | `State.closeLink(s, true)` |
| `hub-link-add` | `Ops.addByLink`: shows a PR the board has, adds a folded one (Team requests, Inactive) to To review (`State.markAdded`), or adds a new one and refreshes |
| `hub-link-open` | `State.linkTarget`, then `openPr` without adding (a board, folded or new PR) |
| `card-remove` | `Ops.remove` |
| `review-fix-close` | `State.closeFixes`, `revealSelected` |
| `review-fix-step` | `State.reviewSelect` |
| `review-fix-move` | `State.reviewSelect(page.cur + delta)` |
| `review-fix-reviewed` | `State.reviewToggle` |
| `review-fix-original` | `State.reviewOriginal` |
| `review-fix-discard` | `State.reviewAsk(s, true)` |
| `review-fix-discard-cancel` | `State.reviewAsk(s, false)` |
| `review-fix-push` | `Ops.reviewEffect(b, cx, "push")` |
| `review-fix-discard-confirm` | `Ops.reviewEffect(b, cx, "discard")` |
| `fixes-close` | `State.closeFixes` |
| `fixes-step` | `State.fixSelect`, `State.fixFocus(s, "steps")` |
| `fixes-move` | `State.fixMove` |
| `fixes-focus` | `State.fixFocus` |
| `fixes-bots` | `State.fixToggleBots` |
| `fixes-reply` | `State.beginReply`, focus `Paths.replyField` |
| `fixes-cancel` | `State.cancelReply` |
| `fixes-post` | `Ops.postReply` |
| `fixes-resolve` | `Ops.resolveThread` |
| `fixes-rerun` | `ACTIONS["card-rerun"]` for the open PR |
| `fixes-update` | U or the strip's button: `State.branchAction` for the open PR, then `Ops.updateBranch` (behind its base) or `State.fixAsk(s, true)` (up to date: the Push empty commit question) |
| `fixes-empty-confirm` | `State.fixAsk(s, false)`, then `Ops.pushEmpty` (`commands.headTree`, `emptyCommit`, `moveBranch` on the head repository) |
| `fixes-empty-cancel` | `State.fixAsk(s, false)` |
| `hub-checks` | The checks popover on a card (its checks mark or V) or on the fixes page's PR (All checks or V): `State.openChecks` and `Refresh.loadCheckList`, or `State.closeChecks` when it is open on that PR |
| `checks-close` | `State.closeChecks` |
| `checks-move` | `State.checksMove` |
| `checks-press`, `checks-pick` | `State.checksPress` or `State.checksPick`, then `openLink` on the check's link, unfolding Passed, or `Refresh.loadCheckList` again after a failed read |
| `fixes-log` | `Fixes.logUrl`, then `openLink` (`cx.open`, or `Fetch.openInBrowser` when Settings say so) |
| `fixes-github` | `openLink` on the step's GitHub page |
| `fixes-press` | `State.fixPress`, then the step's own `fixes-*` action or the card's main action |

The guide page has its own `ACTIONS` table in `src/review-page.luau`, with the same `dispatch` shape and `Keys.action` for keys: `step`, `goto-step`, `next-suggestion`, `peek`, `reveal`, `whole`, `toggle-flow`, `toggle-description`, `toggle-folder`, `toggle-group`, `toggle-file`, `open-all-supporting`, `toggle-help`, `toggle-tree`, `dismiss`, `scroll`, `open-github`, `view`, `toggle-view`, `review-step`, `mark-block`, `mark-change`, `mark-file`, `mark-supporting`, `mark-all`, `decide`, `decide-current`, `goto-suggestion`, `goto-own`, `comment`, `comment-step`, `comment-save`, `comment-cancel`, `open-search`, `search-run`, `search-move`, `search-pick`, `search-go`, `search-close`, `toggle-models`, `toggle-lenses`, `models-slot`, `models-filter`, `models-move`, `models-top`, `models-effort`, `models-pick`, `model-row`, `model-effort`, `edit-lenses`, `open-review`, `toggle-review`, `review-move`, `toggle-item`, `toggle-all`, `verdict`, `edit-summary`, `done-summary`, `submit-review` and `open-posted`. `generate-guide` (the explanation, ⇧G) and `draft-review` (the review comments, ⇧R) start the agent, so `AGENT_ACTIONS` handles them before `dispatch`, in `event` and `key`. `open-github` and `open-posted` open their link through the page's own `openLink`, which follows the hub's `links` setting.

### Keys

`Keys.hubAction(s, key)` picks the mode with `HubState.mode(s)` and maps the key. The README Keys table and `src/view/hub/help.luau` list the same keys for the reader.

| Mode | Keys |
|---|---|
| `board` | `?` help. `/` search. ⌘R or Ctrl+R refresh. Esc `hub-escape`. ⏎ `hub-open`, ⇧⏎ `hub-open-generate`, ⌘⏎ `hub-open-pane`. Space `hub-mark`. ⇧X `hub-mark-stale` on the mine tab. With marks, M `hub-batch-merge` and X `hub-batch-close`. h j k l and the arrows `hub-move`. `.` `hub-next`. T `hub-tab`. I `hub-fold inactive`. R `hub-fold merged` on the mine tab and `hub-fold recent` on the review tab (`State.ROW_FOLD`). ⇧T `hub-fold team` and A `hub-fold approved` on the review tab. F `hub-menu filters`. S `hub-menu sort`. ⇧S or ⇧M `hub-menu settings`. N `hub-link`. V `hub-checks` on the selected card. Any other letter runs the selected card's main or alternative action whose `key` matches (⇧A also runs a main `card-summarize`). |
| `menu` | j k and the arrows `hub-menu-move`. ⏎ `hub-menu-enter`. Space `hub-menu-select`. Esc `hub-menu-close`. In Settings, the review page's model menu keys (`Keys` `modelsKey`: ↑↓ `models-move`, ←→ `models-effort`, Tab `models-slot` (Explanation, Review, Lens), ⏎ `models-pick`, ⌃E `edit-lenses`), other keys type into its search field (`models-filter`), and L sends `hub-links` and ⇧G `hub-guides` while that field is empty. In Filter, Space toggles a saved rule and Enter edits it. In filter editors, Tab switches text/options, Enter applies text and Esc returns without saving; ordinary letters type. While a merge method is typed, ⏎ `hub-method-save` and Esc `hub-method-cancel`. |
| `search` | ⏎ `hub-search-done`. Esc `hub-search-clear`. Up and down `hub-move`. Other keys type, and a change sends `hub-searched` (`Keys.hubAfterTyping`). |
| `link` | ⏎ `hub-link-add`. ⇧⏎ `hub-link-open`. Esc `hub-link-clear`. Other keys type. |
| `confirm` | ⌘⏎ `hub-confirm`. Esc `hub-confirm-cancel`. |
| `help` | Esc or `?` `hub-help-close`. |
| `fixes` | While the Push empty commit question is open, only ⌘⏎ `fixes-empty-confirm` and Esc `fixes-empty-cancel`. Esc `fixes-close`. ⇧L `fixes-log`. ⇧R `fixes-rerun`. U `fixes-update` on a failing check when `State.branchAction` offers one. V `hub-checks`. T `pages-cycle`. j k `fixes-move`. h l `fixes-focus`. ⏎ `fixes-press`. R `fixes-reply`. E `fixes-resolve`. G `fixes-github`. B `fixes-bots`. The card's main action key, and A, ⇧A or O for its alternatives. |
| `checks` | j k and the arrows `checks-move`. ⏎ `checks-press`. ⇧R `card-rerun` while a check fails. Esc or V `checks-close`. |
| `reply` | ⌘⏎ `fixes-post`. Esc `fixes-cancel`. ⏎ is a new line. |
| `review-fix` | Esc `review-fix-close`. ⏎ `review-fix-reviewed`. j k `review-fix-move`. B `review-fix-original`. D `review-fix-discard`. P `review-fix-push`. While asking, ⌘⏎ `review-fix-discard-confirm` and Esc `review-fix-discard-cancel`. Nothing while busy. |

Letter keys act only while the search and add-by-link fields are empty. Keys with Ctrl, ⌘ or ⌥ do nothing except ⌘R and the ⌘⏎ confirmations.

---

## Appendix D. Tests

Run all of them with `/opt/homebrew/bin/luau tests/run.luau`. `tests/run.luau` lists the modules in order.

| Test file | Requires | Pins |
|---|---|---|
| `tests/model_test.luau` | `hub/model` | Placement (`classify`) of every fixture case with its reasons, column order for each sort, next up, the 7-day active window, what counts as feedback, drafts. |
| `tests/github_test.luau` | `github`, `tests/fake-runner.luau` | Every parser over `fixtures/hub/raw-*.json` and that none throws, every `commands` argv, the paged searches and `added` aliases, the retry of a dropped read, the refresh's thread follow-up and a partial threads failure, probe and run, error values. |
| `tests/state_test.luau` | `hub/model`, `hub/state`, `text-field` | The board projection, tabs, filter, sort, search, menus, cards and their actions. |
| `tests/sync_test.luau` | `hub/model`, `hub/sync` | `load` validation, `save` under the cap, `merge` with local facts and pending merges, `diff` and `alerts`, `schedule`. |
| `tests/links_test.luau` | `links` | Link and number parsing, `#prguide-open=` routes, pane choice (`hubEntry`), the status text and watcher timing. |
| `tests/merge_test.luau` | `github`, `hub/model`, `hub/state`, `hub/sync` | Merge-method resolution and detection, merge-failure sources, the refresh carrying pending merges, merge commands and cards. |
| `tests/fixes_test.luau` | `github`, `hub/fixes`, `hub/model` | The fixes page's details, noise filter, steps, excerpts, `git merge-tree` and `git log` readers. |
| `tests/selection_test.luau` | `github`, `hub/model`, `hub/state` | Marks, Merge selected, Close stale, the confirm. |
| `tests/flake_test.luau` | `github`, `hub/model`, `hub/state` | The flake verdict matrix, run parsing, `historyCache` (one read per repo per hour), and where Re-run sits on a card. |
| `tests/rereview_test.luau` | `github`, `hub/model`, `hub/state` | Re-request review after new commits, and where Merge when ready is offered. |
| `tests/agent_fix_test.luau` | `hub/agent-fix` | The engine's exact command sequence for conflicts and bot fixes, the lease take and return, and the conflicts tool run through its interpreter on Windows. |
| `tests/agent_state_test.luau` | `hub/agent-fix`, `hub/state`, `keys`, `text-field` | The agent card lifecycle, its keys and clicks, lease effects. |
| `tests/review_fix_test.luau` | `hub/agent-fix`, `hub/review-fix`, `hub/state`, `keys`, `text-field` | Conflict excerpts from a fix commit, the Push and Discard plans and their results. |
| `tests/moves_test.luau` | `diff`, `moves`, `pr` | Moved blocks across files and within one, the near misses that stay plain changes (short or brace-only blocks, an edited line, a remove-then-add group), `Diff.analyze` carrying moves, and that 3,000 moved lines match in under two seconds. |
| `tests/diff_test.luau` | `diff`, `pr` | A step's block starting at its enclosing function (within `SCOPE_REACH`), the hidden runs and gap labels around it. |
| `tests/groups_test.luau` | `agent`, `file-group`, `file-tree`, `git-output`, `guide`, `pr`, `review`, `state` | Tests and generated files: the path classifier, git's output marking them, the order and sections the page lists files in, what a guide and the agent's diff leave out, and how the supporting area folds and opens them. |
| `tests/model_menu_test.luau` | `model-box`, `keys`, `state`, `view/model-panel`, `view/header`, `view/ui`'s `tern.ui` stubbed | The model menu's Explanation and Review slots with no Off row, Tab, choosing, the Lens slot, the header's Settings button, and the AI row's Generate AI guide and Generate LLM review. |
| `tests/hub_settings_test.luau` | the real `hub/block`, `Host` stubbed, `view/ui`'s `tern.ui` stubbed | Settings: opening focuses the search, typing filters, Tab to Review, a click, the lens, the saved choice, L only with an empty search, and why OMP wasn't found when there is no agent. |
| `tests/platform_test.luau` | `platform`, `Host` fields swapped | Windows: home from `USERPROFILE`, temp from `TEMP`, `;` PATH with quoted entries, PATHEXT names, the first folder winning, `python` and `rundll32`; macOS and Linux keep `HOME`, `/tmp`, `:` PATH, `python3` and `open` or `xdg-open`. |
| `tests/agent_diff_test.luau` | `agent`, `pr` | What the explanation's diff shows as one line (generated, vendored, minified and snapshot files) and the whitespace-only hunks it counts instead of showing, outside Python and YAML. |
| `tests/fold_test.luau` | the real `hub/block`, `Host` stubbed, `view/ui`'s `tern.ui` stubbed | Opening a fold scrolls its header to the top of the board; closing one doesn't scroll. |
| `tests/ci_log_test.luau` | `ci/actions`, `ci/buildkite`, `ci/log` | The log contract and both CI modules on recorded output (`fixtures/hub/ci-logs.luau`): which checks each owns, the exact commands and env, the cut, failures, `Log.refs`, and each module's re-run (once per run or build). |
| `tests/checks_test.luau` | `github`, `hub/checks`, `hub/state`, `keys` | The check list parsed from GitHub (every state mapped), the client's one read, the popover's groups, times and fold, a check that finishes while open, its state on the hub, and its keys. |
| `tests/rerun_test.luau` | `hub/block`, `ci/log` | Re-run failed checks on the hub block: each CI module gets its own failing checks, and a check none owns is named in the toast. |
| `tests/branch_test.luau` | `hub/block`, `github`, `hub/state`, `view/hub/fixes`, `keys` | U on a failing check: the parsed base comparison, the strip's Update branch or Push empty commit, the key, and the question Push empty commit asks before its three GitHub calls. |
| `tests/summary_test.luau` | the real `hub/block` and `agent-host`, `Host` stubbed | Summarize and bot fixes end to end through `ACTIONS`: stale refs, edited comments, timeouts, a closed block, duplicate callbacks, and the unconfined worker on Windows. |
| `tests/tandem_test.luau` | the real `hub/block`, `agent-host`, `tandem`, `Host` stubbed | Tandem ownership, and the shared cache rules it exercises. |
| `tests/prepare_test.luau` | the real `hub/prepare`, `Fetch`, `Prdata` and `AgentHost` functions and `Host` stubbed; `keys`, `hub/state` | Which PRs want a background guide, one at a time, explanation only, a failure not retried at its head, stopping when turned off or closed, the `hub.preparing` lease, and ⇧G in Settings (plain g types into its search). |

`tests/conflicts.sh` drives `tools/conflicts` on throwaway local repos. It is not in `tests/run.luau`.

`tests/tandem_test.luau` mixes Tandem with cache sync. Its scenarios, by what to do with them:

- Skip these, which test Tandem only: `parser`, `placement`, `fetching`, `blockPaths`, `rootPaths`, `staleRead`, `counts`, `agentOverlap`, `terminalAgents`, `staleUpdate`, `readyPush`, `retainedLease`, `preWorktreeLease`, `watchedMerge`, `queuedMerge`, `sharedOwnership`, `unreadableOwnership`, `wholeBoard`, `fixture`.
- Port these without the Tandem flags, because they pin cache sync. `replayedEdits` (replays, heads, `sinceAt`, a queue removal retiring a pending merge), and the store halves of `cachedStartup`, `sharedCache`, `reverseSharedCache`, `delayedRefresh`, `sharedStore` and `mixedAge` (adopting a strictly newer cache, same-stamp writes told apart by `writeId`, a delayed refresh landing on a newer cache, a write never lowering the shared `refreshedAt`). Rewrite each as two or three tabs over one store.

`summary_test` and `tandem_test` drive the real block by swapping `Host` fields and `AgentHost` functions and settling each recorded callback by hand. That style ports well to TypeScript: stub the client, the store and the agent host, and resolve each Promise in the order the scenario names.
