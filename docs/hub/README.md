# PR hub: product and architecture spec

A hub page for PR Guide. It shows every open PR you wrote and every PR waiting on your review, across repos, sorted by who needs to act next. This folder holds the product and architecture spec, reference mockups in `mockups/` and the measured GitHub queries in `queries/`.

**Status:** implemented by parent [#17](https://github.com/jubbydev/tern-pr-guide/issues/17) and sub-issues #2–#20. The build plan and design history remain below as implementation context.

## Start here

1. Serve the repo root: `python3 -m http.server 61440` (the mockups link `docs/tern-tokens.css` and `guide.css` by relative path).
2. Open these pages:

   | Page | What it shows |
   |---|---|
   | http://localhost:61440/docs/hub/mockups/index.html?agent=1 | The hub, with one card in each agent state |
   | http://localhost:61440/docs/hub/mockups/index.html?tab=rev | The Review requests tab, with the add-by-link field |
   | http://localhost:61440/docs/hub/mockups/pr-fixes.html?pr=418 | ⏎ on a Needs fixes card: what needs fixing, at the code |
   | http://localhost:61440/docs/hub/mockups/review-fix.html | Review fix: checking the agent's conflict resolution before pushing |
   | http://localhost:61440/docs/hub/mockups/checks.html?open=1 | The checks popover under a card's checks mark (`?page=fixes&open=1` from the fixes page, `?load=loading` or `?load=error` for those states) |

3. Before touching `src/view/` or `guide.css`, read the repo's `AGENTS.md`, `DESIGN.md` and `docs/ui.md`. Mockups link `docs/tern-tokens.css` and `guide.css` inside a `.gp-root` wrapper.

## Product decisions (settled)

### Structure

Two Tern tabs, one board each. `T` switches between them.

| Tab | Columns | Below |
|---|---|---|
| Your pull requests | Needs fixes · In review · Ready to merge | Inactive, Recently merged (each folded) |
| Review requests | To review · Waiting on author | Inactive, Team requests, Approved, Recently opened (each folded) |

- **Tab counts:** blue, counting only the cards in the your-turn column. Folds never count.
- **Card looks:**
  - Your-turn cards: washed red (yours) or blue (reviews).
  - Waiting cards: neutral.
  - Done cards: green-edged with a ✓.
  - Agent work: purple.
  - Running checks: amber.
- **Header:**
  - Title, search, then "Updated 40s ago" and the Settings button (`⇧S`, also `⇧M`): the review page's model and lens menu (`src/view/model-panel.luau` over `src/model-box.luau`: Explanation | Review, search, models, effort, lens), saving the same kv key `model`, then an "Open links in" toggle, Tern or Default browser (`L` while the search field is empty; kv key `links`, read by the guide too), then "Prepare AI guides in the background" (`⇧G` while the search field is empty; kv key `hub.prepare`, off by default; see Background guides below).
  - The tab row holds the tabs, then **Filter ▾** (`F`, repository selection, title conditions and ignored checks) and **Sort ▾** (`S`).
  - Sort options: Repository (the default, with Priority order inside each repo), Priority, Newest first, Oldest first, Smallest first.
- **Kept out on purpose:** counts in the header, inline keycaps on the tab-row controls (the hint bar lists the keys), and filler notes such as "Nothing needed from you".

### Personal filters

- Filter reuses the existing tab-row menu placement. Repository is one rule with multi-select values;
  title rules support contains, does not contain, starts with and does not start with (literal,
  case-insensitive text). Enabled visibility rules combine with AND across both tabs and row folds.
- Filter · N counts enabled rules. Its menu shows the hidden PR count for the current tab. Space or
  the checkbox pauses a saved rule; ⏎ or its row edits. Tab switches the editor between text and
  options, ⏎ applies, Esc returns without saving; a click outside closes. Clear filters removes
  all rules. Repository choices retain the existing Space-to-toggle and ⏎-to-finish behavior.
- Ignore a check… chooses a repository, then accepts an exact check name or a currently failing
  suggestion. Each ignored check is independently enabled. It suppresses only the checks reason
  from Needs fixes. Raw check counts and state, Ready to merge and merge guards remain unchanged.
  Conflicts, human feedback and failed merges still count. Unknown failures remain actionable.
- Named failures are optional `Checks.failedNames` evidence for the current head. Ordinary hub-f
  stays count-only. A configured repository's failing PRs receive CheckNames reads in batches of
  10, up to 100 contexts per PR; unlisted failures still count. Refresh replaces this evidence,
  checks polling reads names when ignore rules are active, and late on-demand answers are rejected
  if the PR, head or check snapshot was replaced. A failed read cannot waive failures.
- Durable visibility rules narrow Next up across both tabs. Temporary search keeps its existing
  global queue behavior; walking clears only search when needed. Showing a PR explicitly by link
  pauses title rules hiding it, retaining their values.
- Preferences live in `hub.filters.<lowercase viewer>` (schema 1) and in the pane's saved state.
  The account record contains repositories, repositoriesEnabled, titleRules and ignoredChecks;
  navigation is pane-local. The shared PR cache and global status counts retain raw GitHub facts.

### Which column a PR is in

Each PR appears exactly once.

- **Needs fixes:** your PR had activity in the last 7 days and has at least one of the following. Each reason shows as its own red chip.
  - **Merge failed:** the merge queue rejected it. It sorts first.
  - **A failing check that has not been ignored by an enabled repository-scoped rule.**
  - **Feedback from a person:** the reviewer's latest review requested changes, or a thread is unresolved and its author's latest review isn't an approval. Plain comments ("LGTM"), threads whose author later approved, bots and your own comments never count. An approval doesn't clear a failing check or a conflict.
  - **A merge conflict.**
- **In review:** everything else that's waiting on someone else: waiting on review, on one more approval, on checks, or on Tandem. A PR Tandem is working on stays here.
- **Ready to merge:** approved, checks passing, no conflicts.
- **Inactive:** drafts, and PRs with no activity for 7 days, including stale conflicts. Your real data has 16 conflicted PRs, which is why the 7-day gate exists.
- **Recently merged (folded, `R`):** your PRs merged in the last 7 days, newest first, as rows like Recently opened: repo and number, title, when it merged. ⏎ or a click opens one. Merged PRs leave the board (a hub merge drops the card at once; a merge elsewhere drops it at the next refresh, since the searches ask for open PRs), so this is where they go. Never counted, never in Next up.
- **Review requests tab:**
  - **To review:** reviews requested of you by name (a re-review when you had already reviewed), PRs whose review of yours was dismissed, and PRs you added by link. A request that names both you and your team is yours.
  - **Inactive (folded):** what would be in To review but has had no activity for 7 days. PRs you added by link never go here. Nothing here can be selected or closed: these are other people's PRs.
  - **Waiting on author:** you requested changes or commented.
  - **Approved (folded, `A`):** your latest review approved. New commits alone keep it here, with the quiet note "New commits since you approved" under the title. Green done cards, never counted, never in Next up and never selectable. Pasting its link shows it rather than adding it.
  - **Team requests (folded, `⇧T`):** `review-requested:@me` also returns PRs that ask only a team you're on (CODEOWNERS). Those, with no review of yours, not a re-review and not added by link, wait here with a quiet "Requested from @org/team" chip. They are never Inactive, never counted, never in Next up and never selectable. Adding one by link moves it to To review.
- **Re-review rule:** a review request returns to To review only when the viewer is needed again: a request names them (`reviews.requestedMe`) or their latest review was dismissed. A push alone never does. The card reads "Re-review" with "Requested again" (or "Review dismissed"). No LLM is involved.
- **Priority order:**
  - Your-turn columns: by kind first (a person waiting on you beats a machine), then the longest waiting.
  - Ready to merge: the oldest first, since conflicts grow with time.
  - Waiting columns: the newest first.

### Cards and actions

- **Anatomy:** chip line (the job), title, an optional note (what the agent found or why a fix failed), and the repo line ("api #114 · ◌ 1 pending" on the left, the age on the right). The checks mark sits right after repo #num, so it never moves when the card is hovered or selected; the repo name ellipsizes before the number, and the mark is never cut off.
- **Checks mark:** failing checks as a red ✕ and count, unfinished ones (running and queued) as the amber spinner and "N pending", and with neither, a green ✓ and the passed count. A click or `V` opens the **checks popover** under it (`checks.html`): "Checks" and the head commit's short sha, then the checks grouped Failing, Running, Queued, Passed ("· Skipped N" in the Passed header), each row the check's name and "<workflow or app> · <time>" (elapsed while running, "Queued", "Skipped", or "took 1m 31s"). Passed and skipped fold behind "Show N"; a check that finishes while the popover is open stays at the top of Passed. j/k move, ⏎ opens the check's page (or unfolds Passed), ⇧R re-runs failed checks when any fail, Esc closes. While open and a check is unfinished, the list is read again on the 30 s checks timer.
- **Action placement (one rule for every card):**
  - Resting cards show no actions. The chip already names the job.
  - While a card is hovered or selected, its **split button** takes the age's place on the repo line, and nothing else's, the way Gmail swaps a row's date for its actions.
  - Hovered, the button is quiet. Selected, it's filled and shows its key.
  - Alternatives sit behind the attached ▾. Card heights never change.
- **Clicks:** a click opens, like ⏎; ⌘-click or ⇧-click selects for a batch.

| Card | Main action | Behind ▾ / other keys |
|---|---|---|
| Needs fixes | **Fix with agent** (A), or **Hand off to Tandem** for PRs Tandem watches | **Summarize** (⇧A, or A when the only reason is comments) |
| Agent running | **Stop** (A) | |
| Fix ready | **Review fix** (⏎) | **Discard fix** (D, with an inline confirm) |
| Reviewed fix | **Push to branch** (P) | Discard fix (D) |
| Fix failed | **Try again** (A) | Open worktree (O), only while its lease is retained |
| No local clone | **Clone repo** (A) | Choose folder… (O) |
| In review | **Copy link** (C), or **Re-request review** (Q) while a reviewer waits on a re-review: copies "title url" as plain text (Tern's clipboard has no rich flavor; see the clipboard facts) | |
| In review with a bot review | **Fix bot comments** (A); the card stays in In review | Copy link (C) |
| Ready to merge | **Merge** (M) | Merge method for the repo (`,`) |
| To review | **Review** (⏎) | Remove from Review requests (X), only on PRs you added |

### ⏎ on a Needs fixes card (`pr-fixes.html`)

This opens the PR at what needs fixing, in the guided review layout, inside the hub's own pane. The PR is one container with up to three views: **Fixes** (this page, only for a card in Needs fixes with no agent fix to review), **Guided** (only when the PR has a guide) and **Files**. `t` cycles the views that exist, and the tab strip in each page's header (Fixes · Guided · Files, or Fixes · Files) switches by click; both send `pages-cycle` or `pages-view`. Before the PR's review page has loaded, the fixes page's strip shows Fixes · Review, since it can't yet say whether the PR has a guide. ⇧⏎ on a Needs fixes card opens the review page with the guide started and Fixes a tab away. See "Opening a card's PR".

- **Left column:** the problems as steps, grouped Requested changes, Comments, Failing checks, Merge conflicts.
- **Right side:** the code for the selected step.

| Step | Shows | Actions |
|---|---|---|
| Comment or requested change | The thread pinned at its line in the diff | Reply (R), Resolve (E) |
| Failing check | The annotation pinned at its line; with no usable annotation, the log cut to its errors, then the changed lines it names pinned in their files. A check running again reads "Re-running 1m 12s" in amber, and its log "Log from the failed run" | View log (⇧L), Re-run failed checks (⇧R), and Update branch or Push empty commit (U) |
| Merge conflict | "Your branch" and "main" blocks, plus "Main changed this in #415 by @devon" | Fix with agent (A), Resolve on GitHub (G) |

- **All checks:** under the steps, one row ("◌ 2 pending · ✓ 11 passed", with `V`) opens the checks popover under it. The page reads the check list when it opens (1 point), which is also how a failing check that is running again is known.
- **Keys:** h/l move between the steps and the code panel; j/k move within either one; ⏎ goes into the panel, then chooses the highlighted action; R reply, E resolve, ⇧L view log, U update branch or push an empty commit, G open on GitHub (the conflict editor for a conflict), B bot comments, A the card's own action, Esc back to the board with the card still selected.
- **Re-run failed checks (⇧R):** reads the card's failing checks from the details and hands each CI module the ones it owns, all at once: GitHub Actions runs `gh run rerun <run> --failed --repo <repo>` once per workflow run; Buildkite retries the job a check's link names, or lists the build's failed jobs (`bk build view … --recursive --json`) and runs `bk job retry <job>` for each, once per build, with the org in `BUILDKITE_ORGANIZATION_SLUG`. A failing check no module owns shows "Couldn't re-run deploy/preview: no CI module reads it". The sample board doesn't re-run.
- **Update branch or Push empty commit (U):** for a check that can't be re-run, a new head runs every check again. The details' `baseRef.compare(headRef: "refs/pull/<n>/head") { behindBy }` (a fork PR has that ref in the base repository) decides, because GitHub reports `mergeStateStatus` BEHIND only where branch protection requires an up-to-date branch: measured 2026-10-12, tagalog-learning-app/Tagalingo-App#1473 was 20 commits behind main and reported UNSTABLE. The failing check's strip shows, after Re-run, "3 commits behind main" and **Update branch** (`Ops.updateBranch`, `gh pr update-branch`) when `behindBy > 0`; "Up to date with main" and **Push empty commit** when it is 0; neither when the PR conflicts with its base or GitHub gave no count (`State.branchAction`). Push empty commit writes to the branch and can't be undone without a force push, so U turns the button into the inline confirm "Push an empty commit to <branch>?" (Confirm ⌘⏎, Cancel Esc; `route.ask`), and only then `Ops.pushEmpty` makes three calls on the head repository: `gh api repos/<head repo>/git/commits/<head> --jq .tree.sha`, a POST to `git/commits` with that tree and the head as parent ("Empty commit to re-run checks"), and a PATCH of `git/refs/heads/<branch>` with `force=false`, so a branch that moved meanwhile refuses ("Couldn't push an empty commit: the branch moved; refresh and try again"). Both keep the Tandem guard, show the card busy ("Updating…", "Pushing…"), toast "Updated #N with main" or "Pushed an empty commit to #N", and refresh; the refresh that brings the new head reads the open page's check list, so its failing checks show "Re-running". The sample board's #111 is 3 behind and #104 is up to date; neither sends anything ("The sample board doesn't update branches", "The sample board doesn't push commits"), and #104 is Tandem's, so its confirm shows the Tandem error.
- **Check logs:** a failing check with no usable annotation has its log read when the page opens, once per commit, by the CI module that owns it (`src/ci/`): GitHub Actions runs `gh run view <run> --repo <repo> --log-failed --job <job>` and keeps 12 lines before and 3 after each error line (the last 30 when none reads as one, 120 a job at most), dropping the runner's setup before the job's first step unless it holds an error; Buildkite runs `bk build view <org>/<pipeline>/<n> --recursive --json`, then `bk job log <job> --agent --max-tokens 1500` for the first 3 failed jobs (one job when the link names it), with `BUILDKITE_ORGANIZATION_SLUG` set to the link's org so `bk` uses that org's saved token. Each line is typed (`Log.Line`): `Log.classify` reads it as an error, a heading (Actions' `##[group]`, Buildkite's `---`, `+++`, `~~~`, marker dropped), a command (`$ `) or plain, and a left-out run is a gap. The page draws errors on the removed-row tint with a Removed Red bar, headings as muted sans labels, and the error count in the log's header. `Log.refs` finds `path:line` mentions of changed files (a build machine's folder prefix allowed) and the page pins up to 5 of them like annotations, reading those files with `Prdata.readFixes`. The sample board's #111 runs both modules on `fixtures/hub/ci-logs.luau` (the Actions log recorded from the smoke repo; the Buildkite output synthetic in `bk`'s documented shape).
- **Data:** one `details.graphql` call when the page opens (1 point, measured 2026-10-10, and again 2026-10-12 with the base comparison and head branch added), cached in `s.details[key]`. `behindBy` is nil when GitHub returns null, and `branch` (head repository and name) is nil when the fork is gone. A thread's code is its first comment's diff hunk. Conflicts and annotated source come from `Prdata.readFixes` on the repo's checkout (or PR Guide's saved copy when already set up); with neither, the conflict step shows "No local copy of owner/repo". Bot threads are listed apart as "Not counted". Reply and Resolve write to GitHub (`commands.reply`, `commands.resolve`); the sample block applies them to the page only.

### Agent fixes (v2)

- **The agent:** your own `omp`, with the review model and effort from Settings (`⇧S`) or the review page's model menu (`src/agent.luau`, kv key `model`).
- **One PR at a time.** There is no "Fix all".
- **Failed worktree ownership:** the block reconciles failure paths against `Engine.held()` during callbacks and after assigning the engine. A returned worktree has no Open worktree action. A failed lease return keeps the same engine handle; Try again retries its release before another run starts. Closing stops a running engine or retries a settled failed lease return, retaining the handle if return still fails. Fix ready worktrees are preserved.
- **Where it works:** in a treehouse worktree, never in your checkout. It commits there and never pushes. The card goes running → **Fix ready** → **Review fix** (`review-fix.html`) → **Push to branch**.
- **Review fix page (`review-fix.html`):**
  - The diff shows only the agent's resolution. Each line is tagged main, Your branch or Agent.
  - B shows the original conflict.
  - Push unlocks once every conflict is marked reviewed.
- **Token-light conflict pipeline:**
  1. No AI: `git merge origin/<base>` with rerere on. A clean merge reaches Fix ready at zero tokens.
  2. No AI: lockfiles and generated files take the base side, then are regenerated.
  3. AI only for the hunks left, through a small `conflicts` tool: `list`, `show <id>` (base, ours and theirs, a few context lines, and the subjects of commits on each side), `take <id> ours|theirs|both`, `write <id>`, `check`.
  4. Commit in the worktree.
- **Conflicts are fixed by merging the base branch in.** No force push.
- **Summaries:** read-only `omp -p` over the feedback, on click only. The verdict ("Reply to @maria-k") goes on the chip line, with one line per commenter below.
- **PRs Tandem watches** are handed to Tandem: one owner per branch.

### Background guides

- **Off by default.** Settings' "Prepare AI guides in the background" (`⇧G` while its search field is empty, kv `hub.prepare`) turns it on.
- **What gets one:** review requests of the viewer (`reviews.requestedMe`) whose saved guide is missing or was written for another head. Your own PRs and team requests don't.
- **When:** once on start with the cached board, after each refresh, and when the setting is turned on. One PR at a time, through the reader's agent with the explanation model (`AgentHost.explain`, the same run as Generate guide), never the review.
- **Where:** the repo's checkout beside the hub's folder, else PR Guide's saved copy, which the first guide for a repo downloads (`Fetch.checkoutFor`, `Fetch.savedCopy`, `Prdata.openPr`).
- **Failures:** a PR tried at a head is not tried again at that head this session, success or not. Nothing shows on the card.
- **Stopping:** when the block closes or the setting goes off, no new PR starts; the one running finishes.
- **Two windows:** the `hub.preparing` lease keeps a second window from explaining the PR the first one is on. It is read then written, so two windows deciding in the same instant can still both run it.

### Merging

Each repo has one merge setting, stored in kv. It's one of six kinds:

| Kind | How | Confirm |
|---|---|---|
| Squash and merge · Create a merge commit · Rebase and merge | `gh pr merge` | ⌘⏎ inline |
| Merge when ready (GitHub merge queue) | `gh pr merge --auto` | No, it can be cancelled |
| *Merge when ready on an In review card* (any method) | GitHub methods: `gh pr merge --auto --squash\|--merge\|--rebase`; queue: `--auto`; comment and label: the method's command, sent early | No; cancel is `--disable-auto` or the method's cancel |
| Comment a command (`/merge`, `/aviator merge`, plus an optional cancel comment) | `gh pr comment` | No, it can be cancelled |
| Add a label | `gh pr edit --add-label` | No, it can be cancelled |

- **Where the setting comes from (first match wins):**
  1. Set by you.
  2. Declared by the repo: `.aviator/config.yml` means comment `/aviator merge`, and `repository.mergeQueue` means the merge queue.
  3. **Learned** from the repo's last 8 merged PRs: a bot merged right after a person commented the same `/…` command, in at least 3 of the 8 and more than half of them. Checking costs 1 point (`merge-detect.graphql`, together with the declared config). It's shown as a suggestion and asked once: ⌘⏎ saves it as your own setting and merges, Esc declines it for good (`learnedAnswered`).
  4. `viewerDefaultMergeMethod`.
- **Detection runs once per repo and is cached.**
- **The hub never calls GitHub's merge on a repo that merges by comment, label or queue.** Two tools can't own one branch.
- **Queued merges:** the card shows "Commented /merge · waiting for the merge" or "Queued in Aviator". A queue rejection moves the PR to Needs fixes as **Merge failed**, with the reason from GitHub's `RemovedFromMergeQueueEvent.reason` or Aviator's blocked status. For comment merges, failure is known only from a check failing after the comment, or from the bot's reply. That lookup (`merge-failure.graphql`, 1 point for all of them) runs only for PRs whose comment or label merge the hub started and whose head commit has not changed; the lookup reads the latest 10 comments and the head's first 50 check contexts, and counts only what came after the merge was asked for. A merge started outside the hub is not watched.
- **The chooser** (`,` or the ▾ on Merge) lists the six kinds. "Comment a command" and "Add a label" ask for text in the menu's foot: `/merge`, or `/merge | /cancel` to name the cancel comment.

### Adding a PR by link

To review has its own field: "Paste a pull request link to review" (`N`, from either tab).

| Pasted | ⏎ | ⇧⏎ |
|---|---|---|
| A new PR | **Add to review** (lands as "Added by you") | **Open without adding** |
| A review request in Team requests or Review requests' Inactive | **Add to review** (marks it added in `hub.added`, so it lands in To review) | **Open** |
| Any other PR already on the board | **Show on the board** | **Open** |

- **Anything else** shows "A pull request link looks like github.com/owner/repo/pull/123".
- **Search only searches.**
- **After you review it,** `reviewed-by:@me` keeps the PR on the board.

### Telling you something needs fixes

- **On every arrival in Needs fixes:**
  - the card arrives with a fading red ring (good news gets a green wash);
  - the hub's status-line segment flashes red.
- **One `cx:toast` per refresh:**
  - one PR: "#396 needs fixes: merge failed";
  - several: "3 pull requests need fixes".
- **Toast only for:** merge failed, a person's requested changes or comment, and failing checks. **Conflicts only get the ring**, because they arrive in bursts from other people's merges.
- **Never toast** on first load, for inactive PRs, or for something you just did.
- **No system notifications:** plugins have no system notification API (as far as I found).

### Keys

| Key | Action |
|---|---|
| h j k l / arrows | Move: up and down within a column, left and right to the nearest card in the next column |
| ⏎ / click | Open the PR in the hub, replacing the board (Needs fixes cards open at the fixes) |
| ⇧⏎ | Open with the AI guide started |
| ⌘⏎ | Open the PR in a Tern pane of its own (board only; ⌘⏎ confirms an inline question elsewhere) |
| Esc (on a review page) | Back to the board with the card still selected, when nothing on the page is open |
| T (on a PR's pages) | Next view: Fixes, Guided, Files |
| T | Switch tab |
| I | Show or hide Inactive (either tab) |
| ⇧T | Show or hide Team requests (Review requests) |
| A | Show or hide Approved (Review requests; no Review requests card uses A) |
| R | Show or hide Recently merged (Your pull requests) or Recently opened (Review requests) |
| F / S | Filter / Sort menu (menus: j/k, ⏎ or Space, Esc) |
| V | The selected card's checks (on the fixes page, all checks): j/k move, ⏎ opens a check, ⇧R re-runs failed checks, Esc closes |
| ⇧S, ⇧M | Settings: typing searches, ↑↓ model, ←→ effort, ⇧←→ lens, Tab Explanation or Review, ⏎ choose and close, ⌃E edit lenses, L where links open and ⇧G background guides (empty search only) |
| N | Add a PR by link |
| / | Search |
| A, ⇧A, P, D, O, C, M, `,`, X | Card actions (see the table above) |
| ⌘⏎ / Esc | Confirm / cancel inline questions |
| ⌘R | Refresh |

- **Every control has a key.** The hint bar shows only what applies right now: Next up, Move, Open, the selected card's main action (plus Select when it applies), and **? Shortcuts**. `?` opens a grouped panel for the current page: the board shows Move, actions for the selected card, and board shortcuts for the current tab and selection; the fixes page and Review fix show only their own keys. Esc, `?` or a click outside closes it. Board-wide keys appear in the board panel and in the controls' tooltips, not in the bar. The search field and the add-by-link field show their keys inside them.
- **A click and its key run the same action.**
- **Keyboard-driven changes never animate.**

## Data and GitHub cost (measured)

| Call | Cost | Time | When |
|---|---|---|---|
| `docs/hub/queries/hub-f.graphql`: one page of one search, run for each of the 3 searches (author, review-requested, reviewed-by) at once, 20 PRs a page up to 50, with check counts, author types, and the fields `HubPR` needs (size, dates, base branch, auto-merge, last queue removal) | 1 pt a page: 4 for 40 PRs (2 + 1 + 1), at most 9 (the old single query was 11 for any count) | 0.9–3.6 s a page on 40 PRs, 4.4–6.6 s on busy repos | On a change, on focus (debounced to 30 s), and every 5 min while the hub block exists (a block can't observe visibility) |
| `merged.graphql`: the viewer's 20 most recently updated merged PRs (`is:pr is:merged author:@me archived:false sort:updated-desc`; search can't sort by merge time, and a merge updates the PR), run beside hub-f's three searches. Measured 2026-10-12 on jubbydev's account (194 merges in 7 days) | 1 pt | 0.7–0.8 s | With every refresh. A failure leaves the cached list |
| `threads.graphql`: thread authors via `nodes(ids:)`, only for PRs with an unresolved thread whose `updatedAt` changed | 5 pts for 17 PRs (the first 30 threads of each; 9 pts at 50) | 0.7–0.8 s | After hub-f |
| `checks.graphql`: CI state for PRs with running checks | 1 pt for 5 or 42 PRs | 1–1.6 s | Every 30 s while any check is running |
| `check-list.graphql`: every check on one PR's head commit (name, state, times, details link, workflow or app), via `nodes(ids:)`. Measured 2026-10-12 on jubbydev/tern-pr-guide-hub-smoke #17 and a vercel/next.js PR | 1 pt (the cost follows the query's shape, not how many checks come back) | 0.5–0.6 s | When the checks popover or a fixes page opens, and every 30 s while the popover is open and a check is unfinished |
| REST `/notifications` with `If-Modified-Since` | free (304) | | Every 60 s, as the change probe |
| Fixes-page details: threads with path/line/body, changes-requested reviews, failing check runs with annotations, the head branch and how far behind its base it is | 1 pt | | When a Needs fixes PR is opened |
| `merge-detect.graphql`: what a repo declares (`.aviator/config.yml`, a merge queue) and its last 8 merged PRs with `mergedBy` and comments. Measured on the smoke repo 2026-10-10 | 1 pt | | Once per repo, for repos with a Ready card; the result is cached in kv |
| `merge-failure.graphql`: latest comments and head check contexts, via `nodes(ids:)` | 1 pt for any number of PRs (measured for 2) | | After hub-f, only when a comment or label merge is in flight on the same head |

- **Don't** put thread authors inside the search query. Measured at **159 points** per call.
- **Pages, not one query.** GitHub stops a GraphQL query at about 10 s and answers HTTP 502. Measured 2026-10-12 on busy repos (vscode, next.js): the three searches at 50 each in one query got 502 after about 11 s every time, and so did a single search at 50; a 20-PR page took 4.4–6.6 s. A page that fails with a 502, 503 or 504, GitHub's "Something went wrong" timeout body, or the 30 s client timeout is asked again with half the PRs, down to 5; later pages of that search keep the smaller size. Every other GraphQL read retries those failures once; writes never retry.
- **Opt-in check names:** `check-names.graphql` reads names and aggregate counts for failing PRs in configured repositories. It adds calls beyond the ordinary budget below; live cost has not been measured. The default refresh budget is unchanged.
- **Per refresh:** hub-f 4 (40 PRs) + merged 1 + threads 5 + checks 1 = 11, under the 18-point limit the tests hold. A cost depends on the connections a query selects times the PRs it can return (`first:` on a connection under a search doesn't change it), so a page's `$n` sets its cost and an added connection is paid 20 times per page. Alias-added PRs ride on the first `mine` page.
- **Budget:** about 140 pts/hr while the hub block exists (12 refreshes at 11, plus checks). Even the 30 s debounce ceiling (about 2,200/hr at the 18-point limit) fits the 5,000/hr GraphQL budget, which Tandem's pr-watch shares. An open checks popover with a check unfinished adds 1 point every 30 s (at most 120/hr), and only while it stays open.
- **Latency is the real cost.** Always render from the kv cache first, then refresh in the background.
- **Check annotations include noise.** Drop paths under `.github/` and messages like "Process completed with exit code". Measured on Tagalingo-App #1013, the useful one was `src/lib/query-persister.ts:39 Type …`.
- **Conflicted files** come from local `git merge-tree --write-tree --name-only`, not GitHub.
- **Your real data:** 36 open PRs you wrote across 7 repos (20 in Tagalingo-App), 16 with conflicts, and 1 review request.

## Shared Luau contracts

Every issue builds against these types and signatures. An issue that needs a change edits this section in the same PR as the code. Every module starts with `--!strict`, as `src/keys.luau:1` does. Time is `now: number`, in seconds since the epoch, passed in by the caller. Stored times are ISO strings like `"2026-10-09T04:16:06Z"`. No module in this section reads the clock itself. Types are shown unqualified: in code, another module's type is written `Model.HubPR`, `Github.Client`, `Fields.Field` and so on.

**Existing patterns these follow** (read the code before changing them):

- **State** is one mutable record built by `M.new`, with each field commented (`src/state.luau:68-119`, `:133`). `keyed: boolean` marks a change that came from a key and must not animate (`:108-109`).
- **Keys** return `Action = { act: string, value: string? }` (`src/keys.luau:8`) from `M.action(s, key): Action?` (`:98`). A click sends the same action as the key.
- **Glue** is one `ACTIONS: { [string]: Handler }` table and `dispatch` (`src/block.luau:277`, `:445`), inside a `BlockDef<Block>` with `init/title/view/event/key` (`src/block.luau:686-781`; Tern's type is `tern.d.luau:271-291`).
- **Views** are `view(s: State.State, motion: Ui.Motion): Node` (`src/view/page.luau:71`; `Motion` is `src/view/ui.luau:9`).
- **Callbacks** fire once with `(value?, err?)`: `Fetch.findRepo` (`src/fetch.luau:356`), `listAnywhere` (`:457`), `listPrs` (`:482`), `openPr` (`:514`), `submitReview` (`:562`). The hub's GitHub callbacks use the same shape, with a structured `Error` where `fetch.luau` uses a string.

**What each module may `require`:**

| Module | May require |
|---|---|
| `src/links.luau` | nothing |
| `src/hub/model.luau` | nothing |
| `src/hub/fixes.luau` | `model` |
| `src/hub/checks.luau` | `model` |
| `src/github.luau` | `model`, `fixes`, `checks`. No `tern.*` at load; parsers take already decoded tables (`tern.json.decode` runs in the caller). |
| `src/hub/sync.luau` | `model` |
| `src/hub/agent-fix.luau` | `model`, `fixes` |
| `src/hub/review-fix.luau` | `agent-fix`, `fixes` (pure commit excerpts and effect plans) |
| `src/hub/summary.luau` | `model`, `fixes` |
| `window.luau` | `src/links.luau` |
| `src/hub/state.luau` | `model`, `sync`, `fixes`, `checks`, `agent-fix`, `review-fix`, `summary`, `src/text-field.luau`, `src/links.luau` (pure: link parsing and the `#prguide-open=` link). Never `fetch`, `github` or `block`. |
| `src/keys.luau` | `src/hub/state.luau`, plus what it requires today minus `picker` |
| `src/view/hub/*.luau` | `state`, `model`, `fixes`, `checks`, `src/view/ui.luau`, `src/text.luau`. Never `sync` or `github`. |
| `src/fetch.luau`, `src/prdata.luau`, `src/agent-host.luau`, `src/tandem.luau` | `model` and `fixes` for types, `github` for the `Runner` type, `review-fix` for validated command plans, `src/links.luau`, `src/hub/sync.luau` (the recent store), plus what it requires today minus `picker`. prdata, agent-host and tandem run commands through fetch's runners. |
| `src/hub/runtime.luau`, `store`, `lookups`, `tandem`, `prepare`, `refresh`, `details`, `agent-run`, `ops`, `block` | everything above, in that require order; `src/hub/block.luau` is the glue that wires them, and no module requires it |
| `tools/conflicts` | nothing (a standalone script) |

### `src/links.luau` (pure; the picker's link parsing, moved, and the way in's decisions)

```luau
function M.named(text: string): number?            -- "354", "#354" or a PR link -> 354 (picker.luau:179)
function M.linkRepo(text: string): string?         -- "owner/repo" a PR link is in (picker.luau:186)
function M.linkHost(text: string): string?         -- the link's host (picker.luau:191)
function M.reference(slug: string?, number: number): string  -- link, or the bare number without a slug (picker.luau:196)
function M.remoteRepo(url: string): string?        -- "owner/repo" of a git remote URL (picker.luau:202)
function M.sameRepo(a: string?, b: string?): boolean  -- case-insensitive (picker.luau:211)
function M.resolve(text: string, slug: string?): string?  -- ⏎ on pasted text: a PR link as it is; a bare number only with a `slug` (then its link); else nil, so a number alone is refused (the picker's `choice`)

-- The link the hub opens a PR with, and the window's route (`window.luau`) that claims it.
export type OpenRoute = { number: number, root: string, generate: boolean, search: boolean, link: string }
function M.openLink(slug: string, number: number, root: string, generate: boolean, search: boolean): string
	-- https://github.com/<slug>/pull/<n>#prguide-open=<escaped root>[&generate=true][&search=true]
function M.openRoute(url: string): OpenRoute?     -- nil for any other link (GitHub's page opens)
function M.routeArgs(route: OpenRoute): { string }
	-- { "pr=<n>", "repo=<root>", "generate=true"? }; with `search`, "pr=<link>" instead of the number

-- ⌥⌘R and the status segment.
export type PaneLike = { pane: number, block: string?, parked: boolean? }
export type Entry = { kind: "new" | "focus" | "unpark", pane: number? }
function M.hubCandidates(panes: { PaneLike }, focused: number?): { Entry }   -- focused hub, then tiled, then parked
function M.hubEntry(panes: { PaneLike }, focused: number?, answers: ((pane: number) -> boolean)?): Entry
	-- the first candidate that `answers` (window.luau probes with the set-generate event: a dead block raises), else "new"
function M.statusText(toReview: number, needFixes: number): string  -- "PRs · 2 to review · 10 need fixes"; zero parts are left out, both zero is "PRs"
function M.flashing(flashAt: number?, now: number): boolean          -- FLASH_SECONDS (10)
function M.watchDelay(flashAt: number?, now: number): number         -- WATCH_SECONDS (15), sooner when a flash ends first
function M.statusChanged(old: Seen?, new: Seen?): boolean            -- refreshedAt, a count or the flash changed
```

With `search` the root is a folder to look for a checkout in (no clone was found, and PR Guide's own copy of the repo is used): the guide gets the link and resolves it as it does a pasted link, since a saved copy is a bare repo the guide cannot open by path.

### `src/hub/model.luau` (pure rules)

```luau
export type Tab = "mine" | "review"
export type Column = "needs_fixes" | "in_review" | "ready" | "inactive" | "to_review" | "waiting_on_author" | "approved" | "team"
export type Reason = "merge_failed" | "feedback" | "checks" | "conflict"   -- in this order: severity, and the chip order
export type Sort = "repository" | "priority" | "newest" | "oldest" | "smallest"

export type CheckState = "none" | "pending" | "passing" | "failing"
export type Checks = { state: CheckState, passing: number, failing: number, pending: number, failedNames: { string }? }

export type Verdict = "approved" | "changes_requested" | "commented" | "dismissed"
-- A reviewer's latest review (hub-f's `latestReviews`).
export type Review = { author: string, bot: boolean, verdict: Verdict, at: string, oid: string }
-- An unresolved thread, by its first comment's author (threads.graphql).
export type OpenThread = { author: string, bot: boolean }
export type ReviewState = {
	decision: "approved" | "changes_requested" | "review_required" | "none",
	latest: { Review },               -- one per reviewer
	mine: Review?,                    -- the viewer's own latest review
	requestedMe: boolean,             -- a review is requested of the viewer
	requested: { string },            -- logins and team slugs
	teams: { string },                -- the team slugs among them (`... on Team { slug }`); a cache without it is refetched
	unresolved: number,               -- unresolved threads, counted in hub-f
	threads: { OpenThread },          -- authors of the unresolved ones, once threads.graphql ran
	threadsKnown: boolean,            -- false until then: unknown threads never count as feedback
	comments: number,
}

export type MergeFailure = { kind: "queue" | "aviator" | "comment" | "check" | "bot", reason: string }
-- A merge asked for and not finished: the repo's queue, a posted command, or a label.
export type PendingMerge = { method: "queue" | "comment" | "label", at: string }

export type HubPR = {
	key: string,                      -- "owner/repo#123", the repo as GitHub spells it; unique on the board
	id: string,                       -- GraphQL node id, for `nodes(ids:)`
	repo: string, number: number, url: string, title: string,
	author: string, authorBot: boolean,
	role: Tab,                        -- "mine": the viewer wrote it. "review": it is waiting on, or was added for, the viewer
	draft: boolean,
	createdAt: string, lastActivityAt: string,   -- GitHub's createdAt and updatedAt
	headOid: string, baseBranch: string,
	additions: number, deletions: number, files: number,
	checks: Checks,
	conflicts: boolean,               -- mergeable == CONFLICTING
	behind: boolean,                  -- mergeStateStatus == BEHIND
	reviews: ReviewState,
	mergeFailure: MergeFailure?,
	pending: PendingMerge?,
	tandem: boolean,                  -- Tandem watches the branch; filled by the block, never by GitHub
	addedByMe: boolean,               -- on the board through a pasted link; filled from `hub.added`
}

export type Placement = { tab: Tab, column: Column, reasons: { Reason } }   -- reasons is empty outside needs_fixes

export type RateLimit = { cost: number, remaining: number, limit: number, resetAt: string }
export type Error = { operation: string, message: string, rateLimit: RateLimit? }   -- operation is like "gh api graphql: hub"
export type PRRef = { repo: string, number: number }
-- What one GitHub refresh returns, normalized. Defined here so `sync` and `state` can use it without requiring `github`.
export type Refresh = {
	prs: { HubPR },                   -- `tandem` and `addedByMe` false, `pending` nil: the block fills them from local facts
	viewer: string,
	rateLimit: RateLimit,             -- the last call's envelope
	calls: { RateLimit },             -- every call's envelope, in order: each hub-f page as it answered, then threads
	truncated: boolean,               -- a search returned more than 50
	partial: Error?,                  -- threads failed: `prs` still stands, with threadsKnown = false
}

function M.epoch(iso: string): number?                  -- picker.luau:271, moved
function M.ago(iso: string, now: number): string        -- "2h ago" (picker.luau:290), moved
function M.reasons(pr: HubPR, now: number, ignored: { IgnoredCheck }?): { Reason }
function M.placement(pr: HubPR, now: number, ignored: { IgnoredCheck }?): Placement
function M.classify(pr: HubPR, now: number, ignored: { IgnoredCheck }?): Column     -- placement(pr, now).column
function M.botFeedback(pr: HubPR): boolean              -- a bot's latest review or unresolved thread, for Fix bot comments
function M.mergeable(pr: HubPR): boolean                -- ready, not behind, nothing pending: the cards Space may select
function M.selectGroup(pr: HubPR, now: number): ("ready" | "inactive")?, string?   -- the group Space may select it in, or nil and why not; the viewer's Inactive rows (drafts too) always qualify, review requests never do
function M.stale(pr: HubPR, now: number): boolean       -- Inactive for 7+ days of silence and not a draft: what Close stale (⇧X) selects
function M.confirmList(prs: { HubPR }): { shown: { HubPR }, more: number }   -- the first CONFIRM_TITLES (5), then the count left
function M.methodLines(methods: { MergeMethod }): { string }                 -- one line per distinct method: "Squash and merge", "Comments /merge"
function M.size(pr: HubPR): number                      -- additions + deletions
export type TitleOperator = "contains" | "not_contains" | "starts" | "not_starts"
export type TitleRule = { operator: TitleOperator, value: string, enabled: boolean }
export type IgnoredCheck = { repo: string, name: string, enabled: boolean }
export type Filter = { repositories: { [string]: boolean }?, search: string, titles: { TitleRule }? }   -- nil repositories = all
function M.visible(pr: HubPR, filter: Filter): boolean  -- search matches "#n", title, author, repo, base branch
function M.order(prs: { HubPR }, column: Column, sort: Sort, now: number, ignored: { IgnoredCheck }?): { HubPR }

-- Next up
export type NextItem = { key: string, tab: Tab, column: Column, reason: Reason? }
export type NextUp = { item: NextItem, index: number, total: number }
function M.queue(prs: { HubPR }, now: number, ignored: { IgnoredCheck }?): { NextItem }    -- everything that needs the viewer, both tabs, most urgent first
function M.nextUp(prs: { HubPR }, now: number, after: string?, ignored: { IgnoredCheck }?): NextUp?  -- the item after `after`; the first when nil or no longer queued; wraps; nil when none. `index` is the returned item's place (the banner's "n of N")

-- Flakes. Evidence is fetched by github.luau; the verdict is a rule.
export type FlakeEvidence = {
	history: { failed: number, total: number }?,   -- the same check on recent runs of the base branch
	passedBefore: boolean,                         -- it passed on this commit earlier, or on the previous one without a change to the failing area
	text: string,                                  -- the failure text
	annotationPaths: { string },
	changedPaths: { string },
	base: string?,                                 -- the base branch the history counted, for the reason's wording; "main" when nil
}
export type FlakeVerdict = { flaky: boolean, basis: ("history" | "rerun" | "text" | "outside_diff")?, reason: string? }
function M.flake(evidence: FlakeEvidence): FlakeVerdict
	-- An annotation on a changed path is never flaky. `reason` reads "failed 3 of the last 20 runs on main".
	-- History: 3 or more failures in the last 20 runs on the base branch means likely flaky; 1 or fewer means not.
	-- Two is not enough on its own: only another basis (passedBefore, text, outside_diff) makes it flaky.
	-- The thresholds are named constants in this file, pinned by the flake issue's tests:
	-- M.FLAKE_FAILED_MIN = 3, M.FLAKE_FAILED_MAX = 1, M.FLAKE_RUNS = 20. Order of the bases: history, rerun, text, outside_diff.
function M.flakeAll(verdicts: { FlakeVerdict }): FlakeVerdict   -- one verdict for a card: flaky only when every failing check is

-- Merging
export type MergeMethod =
	{ kind: "squash" } | { kind: "merge" } | { kind: "rebase" }
	| { kind: "queue" }                                           -- gh pr merge --auto
	| { kind: "comment", command: string, cancel: string? }       -- gh pr comment
	| { kind: "label", label: string }                            -- gh pr edit --add-label
export type MergeSource = "user" | "declared" | "learned" | "viewer"
export type MergeEvidence = {
	user: MergeMethod?,
	declared: MergeMethod?,           -- .aviator/config.yml, or repository.mergeQueue
	learned: MergeMethod?,            -- from the last 8 merged PRs
	learnedAnswered: boolean,         -- the viewer was asked about `learned` and said no (a yes becomes `user`)
	viewerDefault: "squash" | "merge" | "rebase",
}
export type MergeResolution = { method: MergeMethod, source: MergeSource, ask: boolean }  -- ask: a learned method nobody confirmed yet
function M.resolveMergeMethod(evidence: MergeEvidence): MergeResolution   -- user, declared, learned (unless answered), viewer
```

### `src/hub/checks.luau` (pure; what the checks popover shows)

```luau
export type CheckState = "failing" | "running" | "queued" | "passed" | "skipped"
export type CheckRow = { name: string, source: string?, state: CheckState, startedAt: string?, completedAt: string?, url: string }
export type CheckList = { headOid: string, rows: { CheckRow } }
export type Load = { state: "loading" } | { state: "loaded", list: CheckList } | { state: "failed", reason: string }
export type Popover = { key: string, hl: number, passedOpen: boolean, seen: { [string]: boolean }, from: "board" | "fixes" }
export type Line = { kind: "header", label: string, count: number, skipped: number } | { kind: "check", row: CheckRow, sub: string } | { kind: "more", count: number, fresh: boolean }
export type Mark = { failing: number, pending: number, passed: number }
function M.clock(seconds: number): string                       -- "45s", "6m 24s", "1h 05m"
function M.timeText(row: CheckRow, now: number): string          -- elapsed while running, "Queued", "Skipped", "took 1m 31s"
function M.sub(row: CheckRow, now: number): string               -- "<workflow or app> · <time>"
function M.counts(list: CheckList): Counts / M.unfinished(list): boolean / M.mark(checks: Model.Checks): Mark?
function M.lines(list: CheckList, pop: Popover, now: number): { Line }   -- Failing, Running, Queued, then Passed with what finished while open first and the rest behind "Show N"
function M.choices(lines): { Line } / M.observe(pop, list) / M.rerunning(list?, name): CheckRow? / M.rerunText(row, now): string
```

### `src/hub/fixes.luau` (pure; what the fixes page shows)

```luau
export type ThreadDetail = {
	id: string, group: "requested" | "comment",   -- "requested": the thread's first comment is part of a changes-requested review
	author: string, bot: boolean,
	path: string, line: number?,      -- nil when the thread is on the file or the line is gone
	outdated: boolean,
	body: string,                     -- the first comment
	replies: number, url: string,
	hunk: string?,                    -- the first comment's diff hunk, which ends at the commented line: the page's code for a thread
}
export type ReviewDetail = { author: string, body: string, at: string, url: string }   -- a changes-requested review
export type Annotation = { path: string, line: number, level: "failure" | "warning" | "notice", title: string?, message: string }
export type FailingCheck = {
	name: string, workflow: string?, runId: number?, url: string,
	summary: string?,
	annotations: { Annotation },      -- as GitHub sent them; `usable` drops `.github` paths and "Process completed with exit code"
}
export type Cause = { number: number?, title: string, author: string, sha: string }   -- "Main changed this in #415 by @devon"; author is git's name
export type ConflictHunk = { start: number, branch: { string }, main: { string } }   -- one conflict block, side by side
export type Conflict = { path: string, cause: Cause?, hunks: { ConflictHunk } }
export type FixDetails = {
	key: string, headOid: string, fetchedAt: string,
	reviews: { ReviewDetail },
	threads: { ThreadDetail },        -- unresolved ones only
	checks: { FailingCheck },
	changedPaths: { string },
	conflicts: { Conflict }?,         -- nil until fetch.luau has read local `git merge-tree --write-tree --name-only`
	conflictNote: string?,            -- why `conflicts` is nil: "No local copy of acme/web", "Couldn't read the conflicts: …"
	files: { [string]: string }?,     -- annotated files as the head commit has them (`git show`), for the pinned annotations
	logs: { [string]: Log.Load }?,    -- failed-check logs by the check's details link, for checks with no usable annotation
	behindBy: number?,                -- commits the base has that the head lacks; nil when GitHub can't compare them
	branch: { repo: string, name: string }?,   -- the head branch and its repository; nil when the fork is gone
}

export type Row = { kind: "ctx" | "add" | "del", old: number?, new: number?, text: string }
export type Excerpt = { rows: { Row }, before: number, after: number? }   -- before/after: lines left out
export type MergeTree = { tree: string, files: { string } }
export type Group = "requested" | "comment" | "check" | "conflict" | "failure"
export type Step = { id: string, group: Group, who: string, text: string, path: string?, line: number?,
	thread: ThreadDetail?, review: ReviewDetail?, check: FailingCheck?, conflict: Conflict?, note: string? }

M.GROUPS: { { id: Group, label: string, chip: string } }       -- Requested changes, Comments, Failing checks, Merge conflicts, Merge failed
function M.usable(annotations: { Annotation }): { Annotation }  -- the noise filter
function M.steps(d: FixDetails, pr: HubPR): { Step }            -- in group order; bot threads are no step; a merge failure alone is one "failure" step with its reason
function M.bots(d: FixDetails): { { author: string, count: number } }
function M.chips(steps: { Step }): { string }                   -- the header's "Address changes", "Reply", "Fix checks", "Resolve conflicts"
function M.hunkExcerpt(hunk: string): Excerpt?                  -- the last 8 rows of a diff hunk
function M.fileExcerpt(text: string, line: number): Excerpt?    -- 5 lines either side
function M.parseMergeTree(text: string): MergeTree?             -- `git merge-tree --write-tree --name-only`: tree id, then the conflicted files; "" files when clean
function M.parseHunks(content: string): { ConflictHunk }        -- conflict markers (two-sided or diff3) in `git show <tree>:<path>`
function M.parseCause(output: string): Cause?                   -- `git log -1 --format=%H%x09%an%x09%s`; the number is the subject's "(#415)" or "Merge pull request #415"
function M.conflicts(tree: MergeTree, shown: { [string]: string }, logs: { [string]: string }): { Conflict }
function M.logUrl(check: FailingCheck, repo: string): string    -- the run's page, else the check's own link
```

### `src/github.luau` (the GitHub boundary)

```luau
-- RateLimit, Error, PRRef and Refresh are defined in model.

-- What `tern.process.run` gives and takes, minus the `cx`. src/fetch.luau exports the real runner (shell PATH and all); tests pass a fake.
export type Out = { status: number, stdout: string, stderr: string, timed_out: boolean }
export type Runner = (argv: { string }, opts: { cwd: string?, stdin: string?, timeout_ms: number? }, done: (out: Out) -> ()) -> ()

export type RefreshRequest = { added: { PRRef }, previous: { HubPR }, checkNames: { [string]: boolean }? }   -- previous supplies cached threads when `lastActivityAt` is unchanged
export type Probe = { changed: boolean, lastModified: string?, pollSeconds: number? }   -- REST /notifications
export type ChecksUpdate = { byId: { [string]: { headOid: string, checks: Checks } }, rateLimit: RateLimit }
export type RunRow = { id: number, workflow: string, sha: string, conclusion: string }   -- one Actions run, REST `workflow_runs[]`
export type RepoHistory = { base: string, byWorkflow: { [string]: { failed: number, total: number } } }   -- per workflow: failures among its newest 20 finished runs
export type HistoryCache = { read: (repo: string, base: string, now: number, done: (value: RepoHistory?) -> ()) -> () }   -- one read per repo and branch per hour (M.HISTORY_SECONDS), failures included
export type Detected = { declared: MergeMethod?, learned: MergeMethod?, viewerDefault: "squash" | "merge" | "rebase", checkedAt: string }   -- `checkedAt` is "" from github (it reads no clock); the block stamps it before saving
export type Command = { argv: { string }, stdin: string? }

export type Client = {
	refresh: (req: RefreshRequest, done: (value: Refresh?, err: Error?) -> ()) -> (),
	probe: (since: string?, done: (value: Probe?, err: Error?) -> ()) -> (),
	checks: (ids: { string }, done: (value: ChecksUpdate?, err: Error?) -> ()) -> (),
	checkNames: (ids: { string }, done: (value: ChecksUpdate?, err: Error?) -> ()) -> (),
	details: (pr: HubPR, done: (value: FixDetails?, err: Error?) -> ()) -> (),
	history: (repo: string, base: string, done: (value: RepoHistory?, err: Error?) -> ()) -> (),   -- gh api repos/<r>/actions/runs?branch=<base>&status=completed&per_page=100; keyed by workflow, not check, because the runs API has no job names
	runs: (repo: string, sha: string, done: (value: { RunRow }?, err: Error?) -> ()) -> (),   -- gh api repos/<r>/actions/runs?head_sha=<sha>&status=completed&per_page=50 (the "passed earlier on this commit" basis)
	detect: (repo: string, done: (value: Detected?, err: Error?) -> ()) -> (),
	checkList: (prId: string, done: (value: Checks.CheckList?, err: Error?) -> ()) -> (),   -- check-list.graphql on one PR node id
	run: (command: Command, done: (stdout: string?, err: Error?) -> ()) -> (),   -- executes a command from `commands`
}
export type Decode = (text: string) -> any      -- `tern.json.decode`, passed in so `github` never touches `tern`
function M.client(run: Runner, decode: Decode): Client
	-- Calls never throw: a failed run, a body that isn't JSON data and a rate limit are `Error` values ("Couldn't …: reason").
	-- Argv: `gh api graphql -f query=<text> [-f ids[]=<id> …]`; probe is `gh api -i notifications?per_page=1 [-H If-Modified-Since: <since>]`.
	-- `refresh` reads threads (threads.graphql) only for PRs with an unresolved thread whose `lastActivityAt` differs from `previous`'s.

-- Pure parsers: decoded JSON in, normalized records out. They never throw on a missing field.
function M.parseDetect(raw: any): Detected?                                  -- merge-detect.graphql
function M.parseMergeFailure(raw: any, pending: PendingMerge): MergeFailure? -- one node of merge-failure.graphql; only events after `pending.at` count
function M.parseHub(raw: any): { prs: { HubPR }, viewer: string, rateLimit: RateLimit, truncated: boolean }?
function M.parseThreads(raw: any): { threads: { [string]: { OpenThread } }, rateLimit: RateLimit }?   -- keyed by node id
function M.parseChecks(raw: any): ChecksUpdate?
function M.parseProbe(stdout: string): Probe?             -- `gh api -i`: 200 or 304, Last-Modified, X-Poll-Interval
function M.parseDetails(raw: any, pr: HubPR): FixDetails?
function M.parseCheckList(raw: any): Checks.CheckList?   -- conclusions SUCCESS/NEUTRAL passed, SKIPPED/STALE skipped, FAILURE/TIMED_OUT/CANCELLED/ACTION_REQUIRED/STARTUP_FAILURE failing; statuses IN_PROGRESS running, QUEUED/PENDING/WAITING/REQUESTED queued; StatusContext SUCCESS passed, FAILURE/ERROR failing, PENDING running, EXPECTED queued
function M.parseRuns(raw: any): { RunRow }                                  -- REST actions/runs
function M.parseHistory(raw: any, base: string): RepoHistory                -- cancelled and skipped runs are not counted
function M.evidenceFor(check: FailingCheck, changedPaths: { string }, history: RepoHistory?, runs: { RunRow }?): FlakeEvidence
function M.historyCache(client: Client): HistoryCache

-- Command builders: exact argv, no network. Merging squash/merge/rebase is `gh pr merge`; queue is `--auto`;
-- comment is `gh pr comment`; label is `gh pr edit --add-label`.
M.commands = {
	merge = function(pr: HubPR, method: MergeMethod): Command end,   -- squash, merge, rebase: `gh pr merge <n> --repo <owner/repo> --squash|--merge|--rebase`; queue: `--auto`; comment: `gh pr comment <n> --repo <r> --body <command>`; label: `gh pr edit <n> --repo <r> --add-label <label>`
	cancelMerge = function(pr: HubPR, method: MergeMethod): Command end,   -- queue: `gh pr merge … --disable-auto`; comment: `--body <cancel>`; label: `--remove-label`; raises for a GitHub merge and for a comment with no cancel
	updateBranch = function(pr: HubPR): Command end,
	headTree = function(repo: string, oid: string): Command end,   -- gh api repos/<repo>/git/commits/<oid> --jq .tree.sha
	emptyCommit = function(repo: string, tree: string, parent: string): Command end,   -- POST repos/<repo>/git/commits, --jq .sha
	moveBranch = function(repo: string, branch: string, sha: string): Command end,   -- PATCH repos/<repo>/git/refs/heads/<branch>, force=false
	close = function(pr: HubPR): Command end,   -- gh pr close <n> --repo <repo>, no comment
	requestReview = function(pr: HubPR, login: string): Command end,
	close = function(pr: HubPR): Command end,
	comment = function(pr: HubPR, body: string): Command end,
	reply = function(pr: HubPR, threadId: string, body: string): Command end,
	resolve = function(threadId: string): Command end,
}
```

`threads.graphql` and `checks.graphql` select `number` and not the repository, so a bare number is ambiguous across repos. Both gain `id` and key their results by it (see Verification).

### `src/hub/sync.luau` (pure; cache shapes, diff, schedule)

Luau has no literal types, so `schema` is a `number` in code and `load` accepts only 1. A PR missing from the old cache never arrives in `diff` (it is new or evicted, and nothing says which). `merge` sets `counts.flashAt` to `now` when the Needs fixes count rose. A refresh in flight turns `schedule`'s `refresh` off (nil).

```luau
export type Counts = { toReview: number, needFixes: number, flashAt: number? }   -- what the status segment reads; flashAt is a time
export type Cache = {
	schema: 1,
	refreshedAt: string, viewer: string,
	prs: { HubPR },
	rateLimit: RateLimit?,
	lastModified: string?,            -- the probe's validator
	counts: Counts,
}
export type Added = { [string]: PRRef }       -- hub.added, by key
export type Local = { added: Added, tandem: { [string]: boolean } }
export type MergeRecord = { schema: 1, user: MergeMethod?, declared: MergeMethod?, learned: MergeMethod?, learnedAnswered: boolean, checkedAt: string?, viewerDefault: string? }
export type Opened = { repo: string, number: number, title: string, author: string, at: string }   -- hub.recent, newest first, at most RECENT_CAP

M.RECENT_CAP = 8                      -- picker.luau:62
M.PROBE_EVERY, M.REFRESH_EVERY, M.DEBOUNCE, M.CHECKS_EVERY = 60, 300, 30, 30   -- seconds

function M.load(raw: any): Cache?     -- nil for anything malformed or not schema 1; never throws
function M.save(cache: Cache, capBytes: number, size: (value: any) -> number): any
	-- The value for kv. Drops the oldest `lastActivityAt` first until `size(value) <= capBytes`.
	-- `size` is injected (the block passes `#tern.json.encode(v)`), so this stays pure.
function M.merge(fresh: Refresh, previous: Cache?, localFacts: Local, now: number): Cache
	-- Sets `tandem` and `addedByMe`, carries `pending` over while `headOid` is unchanged, rebuilds `counts`.
function M.loadMerge(raw: any): MergeRecord?
function M.mergeEvidence(record: MergeRecord?, viewerDefault: "squash" | "merge" | "rebase"): MergeEvidence
function M.openedList(saved: any): { Opened }                     -- picker.luau:65, moved
function M.remember(list: { Opened }, opened: Opened): { Opened } -- picker.luau:83, moved

export type Arrival = { key: string, reasons: { Reason }, toast: boolean }   -- toast: any reason but a conflict
export type Changes = {
	firstLoad: boolean,               -- no previous cache: no ring, no toast
	arrivals: { Arrival },            -- entered needs_fixes from outside it, and not suppressed
	good: { string },                 -- entered ready or approved: the green wash
	toast: { text: string, sub: string? }?,   -- one per refresh: "#396 needs fixes: merge failed", or "3 pull requests need fixes"
}
function M.diff(old: Cache?, fresh: { HubPR }, now: number, suppressed: { [string]: boolean }, ignored: { Model.IgnoredCheck }?): Changes
	-- `suppressed` holds the keys the viewer just acted on. Inactive PRs never arrive.
export type Alerts = { toast: { text: string, sub: string? }?, rings: { string }, good: { string } }
function M.alerts(changes: Changes): Alerts   -- what the block shows: the one toast, the keys to ring red, the keys to wash green
	-- The block sets `state.ringed[key]` to "bad" or "good", holds it (about 1.4 s), switches it to "bad-out" or "good-out"
	-- (the CSS transition, `--gp-dur-rare`) and clears it. The toast's level is "error" (Tern has no "warning").
	-- ⌘R is `hub-refresh`: live, a refresh now; in `fixture=cases`, the next `refreshes` entry, wrapping to the first after the last.

export type ScheduleInput = {
	now: number,
	refreshedAt: number?,             -- the last full refresh, re-read from `hub.cache` every tick so windows share work
	refreshing: boolean,
	probedAt: number?,
	probeChanged: boolean,            -- the last probe saw a change that no refresh has covered
	focusedAt: number?,               -- a focus the block has not refreshed for yet
	checksAt: number?,
	running: { string },              -- node ids of PRs with running checks
}
export type Schedule = { probe: number, refresh: number?, checks: number? }   -- seconds from now until due; 0 is now; nil is off
function M.schedule(input: ScheduleInput): Schedule
	-- probe: PROBE_EVERY after the last one. refresh: REFRESH_EVERY after the last, or sooner when a probe saw a change
	-- or the hub regained focus, but never within DEBOUNCE of the last. checks: CHECKS_EVERY, only while `running` is not empty.
```

### `src/hub/agent-fix.luau` (the agent run state machine)

```luau
export type LineTag = "base" | "ours" | "theirs" | "agent"   -- ours is the viewer's branch; theirs is the base branch merged in
export type ResolvedLine = { tag: LineTag, text: string }
export type ConflictHunk = {
	id: string, path: string, start: number,
	base: { string }, ours: { string }, theirs: { string },
	context: { before: { string }, after: { string } },
	subjects: { ours: { string }, theirs: { string } },        -- subjects of the commits on each side
	resolved: { by: "rule" | "agent", lines: { ResolvedLine } }?,
}
export type Stage = "worktree" | "merge" | "rules" | "agent" | "commit"
export type Run = { key: string, stage: Stage, since: number, worktree: string?, hunks: { ConflictHunk }, left: number }
export type Fix = {
	worktree: string, branch: string, base: string,
	headOid: string,                  -- the PR head the agent started from; Push refuses when the remote head moved
	commit: string, hunks: { ConflictHunk }, summary: string, usedAgent: boolean,   -- usedAgent false: a clean merge, zero tokens
}
export type Event =
	{ kind: "stage", stage: Stage } | { kind: "worktree", path: string }
	| { kind: "hunks", hunks: { ConflictHunk } } | { kind: "resolved", id: string, by: "rule" | "agent", lines: { ResolvedLine } }
	| { kind: "committed", commit: string, summary: string } | { kind: "failed", reason: string } | { kind: "stopped" }
export type Outcome =
	{ kind: "running", run: Run } | { kind: "ready", fix: Fix } | { kind: "failed", reason: string, worktree: string? } | { kind: "stopped" }
function M.start(key: string, now: number): Run
function M.step(run: Run, event: Event): Outcome
```

`tools/conflicts` prints JSON on stdout and exits 0 on success, 1 when a hunk is unknown or conflicts remain, 2 on bad usage. It runs in the worktree it is called from and needs no Tern.

| Command | Output |
|---|---|
| `list` | `{ "hunks": [{ "id", "path", "start", "lines" }], "generated": [path] }` |
| `show <id>` | one `ConflictHunk` without `resolved` (a few context lines, bounded) |
| `take <id> ours\|theirs\|both` | `{ "id", "taken" }` |
| `write <id>` | reads the replacement from stdin; `{ "id", "lines" }` |
| `check` | `{ "remaining": number }`; exit 1 when above 0 |

### `src/hub/review-fix.luau` (pure; issue #16)

```luau
export type Line = { tag: AgentFix.LineTag, text: string, label: string?, number: number }
export type Hunk = { id: string, path: string, start: number, by: "rule" | "agent", lines: { Line }, ours: { string }, theirs: { string } }
export type Review = { hunks: { Hunk }, verified: boolean, error: string? }
export type Original = { path: string, start: number, base: { string }, ours: { string }, theirs: { string } }
export type Command = { argv: { string }, cwd: string }
export type Request = {
	kind: string, key: string, selectedKey: string?, routeKey: string?, repo: string, number: number,
	headOid: string, fix: AgentFix.Fix, reviewed: { [string]: boolean }, verified: boolean,
	completion: ("push" | "discard")?,
}
export type Plan = {
	kind: "push" | "discard", request: Request, command: Command?, returnLease: boolean,
	remoteHeadOid: string, next: "refresh" | "needs_fixes",
}
export type Result = { clear: boolean, remoteHeadOid: string, card: "fix_ready" | "needs_fixes" | "refresh" }
function M.allReviewed(fix: AgentFix.Fix, reviewed: { [string]: boolean }): boolean
function M.build(fix: AgentFix.Fix, files: { [string]: string }, details: Fixes.FixDetails?, originals: { [string]: Original }?): Review
function M.lines(hunk: Hunk, before: boolean): { Line }
function M.readCommands(fix: AgentFix.Fix): ({ Command }?, string?)
function M.plan(action: "push" | "discard", request: Request, confirmed: boolean?, remoteRepo: string?): (Plan?, string?)
function M.result(plan: Plan, pushed: boolean, returned: boolean): Result
```

`build` locates each recorded resolution plus bounded context exactly once in the immutable commit's
file. Missing, changed or ambiguous resolutions lock Push. Context at the conflict tool's 240-character
preview cap is matched as a prefix; all other context and every resolution line must match exactly.
Displayed context comes from the commit in full. It never shows unrelated commit changes.
The retained journal's full original sides are authoritative because #15's `show` caps side previews.
Agent-write lines copied exactly from those sides are tagged ours/theirs; lines common to both are
base. Lines with no side match remain agent-written. #12's `FixDetails` is reused only when path,
start and both sides agree exactly. This avoids reading a newer conflict after a refresh. `theirs`
displays as main, `ours` as Your branch, `agent` as Agent, and `base` has no ownership badge. Every
line keeps its exact text. Duplicate or missing ids lock the all-reviewed gate; zero hunks pass.

`plan` runs no effects. A refused P produces no process plan. A permitted P contains one plain
`git -C <worktree> push https://github.com/<head repo>.git <commit>:refs/heads/<branch>` command.
Confirmed D contains no process or remote write and requests the retained engine's lease return.
`result` permits clearing state only after return succeeds, and for Push only after push succeeds too.
The supplied remote head stays unchanged on Discard. `completion = "push"` produces a return-only
retry; `completion = "discard"` requires confirmation again and forbids Push.

### `src/hub/summary.luau` (pure; read-only Summarize)

```luau
export type Summary = { verdict: string, comments: { { author: string, text: string } } }   -- "Reply to @maria-k", then one line per commenter
function M.prompt(details: FixDetails): string
function M.parse(text: string): Summary?
function M.onlyComments(details: FixDetails): boolean    -- the only reason is comments, so A summarizes
function M.current(details: FixDetails, pr: HubPR): FixDetails   -- only the feedback still live on the PR (see Issue #19)
function M.plan(command: string, model: string, effort: string?, prompt: string): { string }?   -- the read-only argv, nil when a field is unsafe
```

### `src/hub/state.luau` (interaction state and the prepared board)

```luau
export type FilterEdit = { index: number?, operator: Model.TitleOperator, repo: string?, field: Fields.Field, typing: boolean }
export type Mode = "board" | "search" | "link" | "menu" | "confirm" | "help" | "fixes" | "reply" | "review-fix" | "checks"
export type MenuId = "filters" | "title-filter" | "check-repository" | "check-filter" | "repositories" | "sort" | "settings" | "merge" | "actions"
export type CardAction = { act: string, value: string?, label: string, key: string?, confirm: boolean }

export type AgentFixState =
	{ kind: "no_clone", slug: string }
	| { kind: "running", run: AgentFix.Run }
	| { kind: "ready", fix: AgentFix.Fix, reviewed: { [string]: boolean }, review: ReviewFix.Review?, completion: ("push" | "discard")? }    -- `reviewed` holds reviewedConflictIds; completion retains cleanup ownership
	| { kind: "pushing", fix: AgentFix.Fix }
	| { kind: "failed", reason: string, worktree: string? }
-- A ready fix is "reviewed" once `reviewed` holds every hunk id: State.reviewed(fix, reviewed): boolean.

-- A pill on a card's chip line; `kind` picks its look. The checks spinner is on the meta line, never a chip.
export type Chip = { text: string, kind: "bad" | "bad-soft" | "info" | "wait" | "done" | "agent" }

export type Card = {
	pr: HubPR, column: Column, reasons: { Reason },
	chips: { Chip },                  -- the job, or who the card waits on; empty on done cards
	detail: string?,                  -- the first job's detail, shown after the chips ("Conflicts with main")
	detailKind: ("bad" | "info")?,    -- the detail's color: red on your PRs, blue on review requests
	main: CardAction?,                -- the split button's action
	more: { CardAction },             -- behind the attached ▾
	agent: AgentFixState?, summary: Summary?, merge: MergeResolution?,
	note: string?,                    -- a merge in flight: "Commented /merge · waiting for the merge", "Queued in Aviator", "In the merge queue"
	asking: string?,                  -- an inline question ("Squash and merge #412?"): Confirm (⌘⏎) and Cancel (Esc) replace the split button
	busy: string?,                    -- an action in flight ("Merging…", "Updating…")
	ring: ("bad" | "good")?,          -- the arrival ring, until it fades
	selected: boolean, marked: boolean,
}
export type RepoOption = { repo: string, count: number, on: boolean }
export type CardFold = { column: Column, cards: { Card }, open: boolean }   -- column "inactive" or "team"

-- Everything a view reads, built by State.project. Views never filter, sort or classify.
export type BoardData = {
	tab: Tab,
	columns: { { column: Column, cards: { Card } } },   -- the tab's columns, left to right, filtered and ordered
	folds: { CardFold },                                -- the tab's card folds in State.FOLDS order: Inactive on Your pull requests; Inactive, Team requests, Approved on Review requests
	recent: { Opened },                                 -- the fold under "Review requests", after the card folds
	grid: { { string } },                               -- keys per column, for h j k l
	counts: { mine: number, review: number },           -- your-turn cards per tab: the blue counts
	repositories: { RepoOption },
	open: { recent: boolean },                          -- whether Recently opened shows its rows (a card fold carries its own `open`; a search opens every fold with matches)
	nextUp: NextUp?,
	hidden: number, -- current tab PRs excluded by saved visibility rules
	empty: boolean,
}

export type State = {
	prs: { HubPR }, now: number,
	board: BoardData,                 -- rebuilt by State.project after any input below changes
	tab: Tab,
	selected: string?, marked: { [string]: boolean },
	repositories: { [string]: boolean }?, repositoriesEnabled: boolean,
	titleRules: { Model.TitleRule }, ignoredChecks: { Model.IgnoredCheck }, filterEdit: FilterEdit?,
	sort: Sort,
	search: Fields.Field, link: Fields.Field,
	mode: Mode, menu: MenuId?, menuCursor: number,
	confirm: { kind: string, keys: { string } }?,   -- kind "merge" (a GitHub method) or "learned" (the suggested comment command)
	methodEdit: { repo: string, kind: "comment" | "label", field: Fields.Field }?,   -- the merge menu is asking for a command or a label
	folded: { [string]: boolean },    -- true: the fold is closed; inactive, team and recent start closed. One `inactive` flag serves both tabs
	recent: { Opened },               -- hub.recent, newest first, set by the block
	walking: boolean,                 -- Next up is being walked: the banner shows "2 of 11"
	ringed: { [string]: "bad" | "good" },
	agents: { [string]: AgentFixState },
	details: { [string]: FixDetails }, summaries: { [string]: Summary },
	merges: { [string]: MergeResolution },    -- by repo
	acted: { [string]: boolean },     -- cards the viewer just merged or updated: the block hands these to `Sync.diff` as `suppressed`
	busy: { [string]: string },       -- by card key: the action in flight
	refreshedAt: string?, loading: boolean, error: Error?,
	agent: Agent.Agent?,              -- what Settings picks for: the reader's agent once found, or a sample board's
	models: ModelBox.ModelBox?,       -- Settings' model and lens menu (src/model-box.luau), while menu is "settings"
	keyed: boolean,                   -- as src/state.luau:108
	born: { [string]: string }, booted: boolean,   -- arrival motion, as src/state.luau:113
}

function M.new(prs: { HubPR }, now: number, saved: any): State
function M.setRecent(s: State, recent: { Opened })   -- hub.recent; builds BoardData.recent (Review requests only, narrowed by the search)
function M.recentKey(opened: Opened): string
function M.recentRow(s: State, key: string): Opened?
function M.selectedRecent(s: State): Opened?
function M.replace(s: State, prs: { HubPR }, now: number, refreshedAt: string?)   -- a refresh's PRs: sets time, clears loading and error, re-projects
function M.project(s: State)                 -- recomputes s.board from s.prs and the inputs
function M.mode(s: State): Mode
function M.reviewed(fix: AgentFix.Fix, reviewed: { [string]: boolean }): boolean

-- Transient ownership facts from Block; never stored in State and never contain an engine.
export type AgentFlightFacts = {
	settled: boolean, starting: boolean, releasing: boolean, busy: boolean, worktree: string?,
}
function M.agentFlight(s: State, key: string, facts: AgentFlightFacts): "wait" | "release" | "forget" | "ready"
-- Reconciles a failed card's path with the held lease. Block retains the handle for
-- wait/release/ready; only forget permits dropping it. starting guards synchronous callbacks.

-- The fixes page (#12): a route over the board. `s.route = { kind = "fixes", key, cur, focus, item, loading, error, bots, resolved, replies, reply, busy }`.
function M.openFixes(s: State, key: string): boolean / M.closeFixes(s)   -- Esc returns to the board with the card still selected
function M.prOf(s: State, key: string): HubPR? / M.fixDetails(s) / M.fixSteps(s) / M.fixStep(s) / M.fixLeft(s)
function M.fixItems(s: State, step: Fixes.Step?): { string } / M.fixMain(s): CardAction?   -- the panel's actions; the card's own main action
function M.branchAction(s, key): BranchAction?   -- { kind = "update", behind } | { kind = "empty", branch }: what U does, from the details at the head
function M.fixAsk(s, ask: boolean)                -- the Push empty commit question (`route.ask`)
function M.fixSelect(s, index) / M.fixMove(s, delta) / M.fixFocus(s, "steps" | "panel") / M.fixPress(s): string? / M.fixToggleBots(s)
function M.beginReply(s): boolean / M.cancelReply(s) / M.setDetails(s, details)

-- The checks popover: mode "checks" over the board or the fixes page. `s.checks: Checks.Popover?` is { key, hl, passedOpen,
-- seen, from }; loads are cached per "key@headOid" in `s.checkLists` as a Checks.Load (loading | loaded | failed).
function M.openChecks(s, key): boolean / M.closeChecks(s)   -- closing returns to the fixes page when it is open
function M.checkLoad(s, key): Checks.Load? / M.checksWanted(s, key): boolean / M.setCheckLoad(s, key, headOid, load)
function M.checkLines(s): ({ Checks.Line }, Checks.Load?) / M.checksMove(s, delta) / M.checksFailing(s): boolean
function M.checksPress(s): ChecksPress? / M.checksPick(s, index): ChecksPress?   -- { kind: "open", url, name } | { kind: "expand" } | { kind: "retry" }

-- #16 extends Route.kind to "fixes" | "review-fix" and adds original: boolean?, ask: boolean?.
-- All existing fixes/reply fields remain. ReviewPage is the prepared view data:
export type ReviewPage = {
	pr: HubPR, fix: AgentFix.Fix, review: ReviewFix.Review?, reviewed: { [string]: boolean },
	current: ReviewFix.Hunk?, lines: { ReviewFix.Line },
	count: number, all: boolean, cur: number, original: boolean, ask: boolean,
	busy: boolean, loading: boolean, error: string?, progress: string?, completion: ("push" | "discard")?,
}
function M.openReviewFix(s: State, key: string): boolean
function M.reviewPage(s: State): ReviewPage?
function M.reviewSelect(s: State, index: number)
function M.reviewToggle(s: State, index: number?)
function M.reviewOriginal(s: State)
function M.reviewAsk(s: State, ask: boolean)
function M.reviewRequest(s: State): ReviewFix.Request?
-- closeFixes also closes Review fix, preserving the selected card.

-- Card actions (#7). All pure; the block runs the effects.
function M.mergeMethodFor(s: State, pr: HubPR): "squash" | "merge" | "rebase"   -- the repo's resolved method when it is a GitHub one, else squash (viewerDefaultMergeMethod arrives with #10's detection)
function M.mergeStep(s: State, pr: HubPR): "confirm" | "ask" | "run"   -- M on a card: a GitHub method asks first, a learned command asks once, a chosen or declared comment, label or queue runs at once
function M.setMerge(s: State, repo: string, resolution: MergeResolution)   -- the block resolves a repo's record into the board
function M.setPending(s: State, key: string, pending: PendingMerge?)       -- a merge in flight (or cleared)
function M.beginMethodEdit(s: State, kind: "comment" | "label") / M.cancelMethodEdit(s) / M.methodOfEdit(s): MergeMethod?   -- the merge menu's text field
function M.askMerge(s: State, key: string): boolean      -- opens the "Squash and merge #n?" question; mode "confirm", `confirm = { kind = "merge", keys = { key } }`
function M.cancelConfirm(s: State)
function M.setBusy(s: State, key: string, text: string?)
function M.dropPr(s: State, key: string)                 -- a merged PR leaves the board
function M.branchUpdated(s: State, key: string)          -- behind = false, checks pending and the details' behindBy unknown, until a refresh says more
function M.linkTarget(s: State): LinkTarget              -- "empty" | "invalid" | "new" | "folded" | "board": what the add field's text names (github.com links and owner/repo#123 only); "folded" is a review request in Team requests or Inactive
function M.markAdded(s: State, key: string)              -- ⏎ on a "folded" target, after the block wrote hub.added: the PR moves to To review
function M.openLink(s: State) / M.closeLink(s: State, clear: boolean)   -- N: Review requests with mode "link"
function M.show(s: State, key: string): boolean          -- selects a PR, clearing a search or filter that hides it and opening its fold
function M.fold(s: State, column: Column): CardFold?      -- the tab's Inactive, Team requests or Approved fold
function M.isFold(column: Column): boolean               -- "inactive" and "team" show in folds, not columns
function M.walk(s: State): boolean                       -- `.` and the banner: selects BoardData.nextUp's item, switching tab, clearing only a temporary search that hides it; durable filters narrow the queue; sets `walking`. Any other selection clears `walking`
function M.nextCard(s: State): Card?                      -- the banner's item as a Card (its chip), whichever tab it sits on
function M.withAdded(added, ref): (Added?, string?)      -- hub.added with `ref`, or why not (the 50 cap)
function M.canonicalAdded(added, prs): (Added, boolean)  -- keys an added PR by the repo's own spelling
function M.unadd(s: State, key: string)                  -- X: a PR still requested of the viewer or a team, or reviewed by them, stays
function M.openPlan(slug, number, generate, root: string?, why: string?, dir: string): OpenPlan   -- open this link, or refuse with this toast
```

Every file in `src/view/hub/` exports `function M.view(s: State.State, motion: Ui.Motion): Node`, plus `M.layer(s): Node?` where it has an overlay.

### `src/keys.luau` (hub keys)

```luau
function M.hubAction(s: HubState.State, key: Key): Action?   -- the hub's counterpart of `M.action` (keys.luau:98). ⇧⏎ sends `hub-open-generate`; `R` sends `hub-fold=recent`, `⇧T` sends `hub-fold=team` and `A` sends `hub-fold=approved` on the Review requests tab
function M.hubAfterTyping(mode: HubState.Mode, outcome: Fields.Outcome): Action?   -- after a key typed into the search field
```

`I` shows or hides Inactive on either tab, `⇧T` shows or hides Team requests, `A` shows or hides Approved and `R` shows or hides Recently opened (a fold is a control, so it has a key). Opening a fold, by key or by its header, scrolls the board so the fold's header (`Paths.foldHead`) sits at the top, through the same `reveal` frame op that keeps the selected card in view; closing one doesn't scroll. `j`/`k` past the last card walk the open folds in order. A Recently opened row is selected by `State.recentKey` (`rc:<repo>#<n>`), moved to by `j`/`k` after the last card, and opened by ⏎ or a click. A card's action keys (`A`, `⇧A`, `C`, `M`, `U`, `,`, `X`) come from the selected card's `main` and `more`, so a click and a key send the same `Card.main.act`.

`M.pickerAction` (`:109`) is deleted with the picker. Typing modes (`search`, `link`) return nil for letters, as `searchKey` does (`:22`).

### `src/hub/block.luau` (glue) and `src/hub/runtime.luau` (the `Block` record)

```luau
export type Timers = { probe: TimerHandle?, refresh: TimerHandle?, checks: TimerHandle?, debounce: TimerHandle?, ring: TimerHandle? }
-- #5 declares `s`, `fixture`, `generate` and `agent`; the GitHub client, cache, timers and flights arrive with #4.
export type Block = {
	s: State.State, cache: Sync.Cache?,
	agent: Agent.Agent?,              -- the reader's omp, once found (never with a fixture)
	github: Github.Client, timers: Timers,
	flights: { refresh: boolean, checks: boolean, probe: boolean },   -- one call of each kind at a time
	fixture: string?,                 -- `fixture=cases`: no network, no timers
	generate: boolean,                -- ⏎ opens the PR with the AI guide started
	pages: Pages,                     -- hub/pages: the opened review pages (up to 3, least recent first), the one on show and the checkouts being found; never in State, never saved
	sched: { probedAt: number?, probeChanged: boolean, focusedAt: number?, checksAt: number?, refreshTried: number?, lastModified: string? },   -- what `Sync.schedule` reads; `refreshTried` keeps a failed refresh from retrying at once
	closed: boolean,
	refetch: boolean,                 -- a refresh was asked for while one ran (an add, remove, merge or update): run another when it ends
	show: PRRef?,                     -- a PR just added by link: selected and scrolled to when the refresh brings it
}
export type Saved = { tab: Tab, sort: Sort, repositories: { string }?, folded: { [string]: boolean } }
-- `BlockDef<Block>`: init(cx, args, saved), title, view, key, event, save — as src/block.luau:686.
```

The hub has its own `ACTIONS` table, sent by clicks (`event`) and by `Keys.hubAction` (`key`). The work its entries start lives in `hub/ops`, `hub/agent-run`, `hub/details`, `hub/tandem` and `hub/refresh`; the kv reads and writes are `hub/store`'s and `hub/lookups`'; timers go through `Host.timer`, toasts through `cx:toast`. A window can send it an action event; `hub-focused` and `set-generate` are the two the window half sends.

### `src/fetch.luau` (additions)

`src/fetch.luau` keeps the command runners (local git, treehouse, `omp` and Tandem's CLI run through them from `src/prdata.luau`, `src/agent-host.luau` and `src/tandem.luau`), the recent store (`recentPrs`, `rememberPr`, and `migrateRecent`, which the hub runs on first load), and one new export: `M.runner: Github.Runner`, which resolves `gh` and the shell's PATH the way `run` does (`:69-121`). The fixes page adds `Prdata.readFixes(repo, pr, paths, done)` in `src/prdata.luau` (fetches the PR's refs, runs `git merge-tree`, then `git show` and `git log` per conflicted file and `git show` per annotated path; returns text as `FixRead`) and `M.readySavedCopy(slug)` (PR Guide's saved copy, only when already set up). The agent engine and Fix bot comments add their functions to `src/agent-host.luau`, and the Tandem hand-off to `src/tandem.luau`, each in the `(value?, err?)` style above.

Issue #16's settled boundary signatures (`M` is `src/agent-host.luau`):

```luau
export type AgentFixRead = { files: { [string]: string }, diff: string, originals: { [string]: ReviewFix.Original }? }
function M.readAgentFix(fix: AgentFix.Fix, done: (AgentFixRead?, string?) -> ())
function M.pushAgentFix(plan: ReviewFix.Plan, canPush: () -> boolean, done: (boolean?, string?) -> ())
function M.returnAgentFix(path: string, done: (boolean?, string?) -> ()) -- existing signature, unchanged
```

`readAgentFix` executes read-only diff/show/git-dir plans, only while the exact engine holds the
worktree. It reads full original sides from the private conflict journal and validates the journal's
identity against `fix.headOid`; a clean merge needs no journal.
`pushAgentFix` validates the gate again, reads head refs and the actual head repository through the
runner, and checks `git ls-remote` against `fix.headOid`. Fork branches use their head repository.
`canPush` revalidates the selected PR, route, fix, ticks and flight before each process begins.
The refspec names the reviewed commit directly and uses neither force flag. A remote already at
`fix.commit` reconciles a lost successful response without a second push. A different remote head
refuses. Ordinary Git fast-forward protection remains in force if the head races the preflight.
Only successful `returnAgentFix`, with `held() == nil` and `busy() == false`, clears the active slot.
No read, route entry or agent completion pushes automatically.

## How this maps onto Tern

### Registration and the one hub per window

- **Registration.** `plugin.toml` gets `[[blocks]] id = "hub"` beside `guide` (`plugin.toml:9-12`), with `palette = false` as `guide` has, because the commands open it. `host.luau` gains `tern.block.define("hub", require("./src/hub/block"))` (`host.luau:1`; `tern.block.define` is `tern.d.luau:1885-1887`). The module returns a `BlockDef<Block>` with `init`, `view`, `key`, `event` and `save` (`tern.d.luau:271-291`). Its pane kind is `prguide.hub`.
- **`openHub(cx, generate)`** lives in `window.luau` and replaces `pick` (`window.luau:2-10`). It scans `cx.session:panes()` (`tern.d.luau:1445`) for a pane whose `block == "prguide.hub"` (`PaneInfo.block`, `:392`).
  - Found and parked (`PaneInfo.parked`, `:377`): `cx.layout:unpark(pane)` (`:1487`), which deals it into the current tab.
  - Found otherwise: `cx.layout:focus(pane)` (`:1466`).
  - Not found: `cx:new_block("prguide.hub", args, "tab")` (`:1596`), with `args = { "generate=true" }` when `generate`.
  - Opening while a hub exists sends it `cx.session:event(pane, { ev = "action", id = "main.hub", act = "set-generate", value = "true" })` (`:1443`), with `"false"` for ⌥⌘R so a hub opened for AI guides does not stay that way. **[INFERENCE]** that an action event without a node id reaches the block's `event`; the event carries `id = "main.hub"`, the hub's root node, which the view always has, so it does not depend on it. `window.luau` sends `hub-focused` the same way.
- **Callers.** The ⌥⌘R command (`review`), the ⌥⇧⌘R command (`generate`) and the status segment all call `openHub`. Command ids stay, so existing key bindings and `plugin.prguide.review` keep working. Their palette titles become "PR hub" and "PR hub, AI guides". The **New PR Guide sample block** command stays, and a **New PR hub sample block** command (`hub-sample`) opens `prguide.hub` with `fixture=cases`.
- **Block arguments** follow `options` in `src/block.luau:452-471`: `name=value`, unknown names rejected with a message. The hub takes `generate=true|false` and `fixture=<name>`.

### Opening a card's PR

The hub is the PR's container: ⏎, a click and ⇧⏎ open the PR's review page in the hub's own pane, and ⌘⏎ opens it in a pane of its own (the steps below).

**In the hub (`src/hub/pages.luau`).** `Pages.plan` runs steps 1 and 2 below up to the link; `Links.openRoute` and `Links.routeArgs` (what `window.luau` does in step 3) turn it into the guide's arguments, and `ReviewPage.init(cx, args, "main", hosted)` builds the page under the hub's own `main` root instead of a new block. A sample board (`fixture=`) has no network: it opens the bundled sample (arguments `{}`). While a page shows, the hub's `view` returns the page's `{ main, layer }` verbatim and its `title` is "Review · #N"; `key` and `event` go to the page, except the hub's own `hub-focused` and `set-generate`, Esc at the page's rest (`pages-back`: back to the board, closing the fixes page under it, with the card still selected), `t` when Fixes is one of the views (`pages-cycle`) and a click on the Fixes tab (`pages-view=fixes`).

- **The host hook.** `ReviewPage.init`'s optional fourth argument is `State.Hosted = { fixes: boolean }`, kept on the page's state: it adds the Fixes tab, hands `t` to the host and shows "esc board" in the hint bar and `?` panel. The guide block passes nothing and is unchanged. The page also exposes `atRest` (loaded and reading with no search, composer, panel, help or focused suggestion, or not loaded), `reading`, `views`, `current`, `setView`, `unsaved`, `startGuide` and `tabsPath`.
- **Views.** `src/hub/page-views.luau` (pure) holds `views(fixes, pageViews)`, `next` (what `t` does), `tabs` and `victims`. A PR's views are Fixes (a card in Needs fixes with no agent fix to review, or the fixes page already open on it), then Guided and Files, or Files alone for a PR with no guide, or "review" for a page not loaded yet.
- **Kept pages.** `Block.pages` keeps the last 3 pages opened, least recent first, each with the PR, the card it came from and its page: reopening the PR shows it at once with its marks, comments and any guide in flight (scroll resets). Never in `State`, never saved. A page beyond the limit is dropped, oldest first, unless it holds work no file has (`ReviewPage.unsaved`: text in the composer, the reader's own comments, an edited summary, or an agent run in flight; the page's review comments from the agent live in the checkout's review file, and the reader's own live only in memory), so more than 3 can stay. ⇧⏎ on a kept page starts its guide (`ReviewPage.startGuide`).

`BlockCx` has no `new_block`; `WindowCx` does (`tern.d.luau:1141-1160`, `:1596`). The block therefore asks the window half to open it:

1. The block resolves the card's `owner/repo` with the existing resolver: `Fetch.checkoutFor(near, dir, slug, done)` (`src/fetch.luau:388`), then `Fetch.savedCopy(host, slug)` (`:445`) when it finds none. `dir` is `cx.cwd` (`tern.d.luau:1145`), else `HOME`. When neither gives a repo, the block shows a toast with the reason and opens nothing.
2. It calls `cx:open(url)` (`tern.d.luau:1134-1135`, which goes through the window's `route.link`) with `https://github.com/<owner>/<repo>/pull/<n>#prguide-open=<url-encoded root>`, plus `&generate=true` for ⇧⏎ or ⌥⇧⌘R. When no checkout exists but PR Guide can make its own copy, `root` is the folder searched and the link ends `&search=true`: the route then answers `pr=<link>` so the guide resolves it as it does a pasted link. The resolver is `Pages.plan` in `src/hub/pages.luau`; `openPr` in `src/hub/block.luau` calls it for ⌘⏎ and the add-by-link field's ⇧⏎, which open a pane of their own.
3. `window.luau` registers `tern.route.link` (`:1928`) and claims only links carrying `#prguide-open=`, answering `{ block = "prguide.guide", args = { "pr=<n>", "repo=<root>", "generate=true"? } }` (`RouteDecision`, `:1011-1025`). The guide requires `repo=` with `pr=` (`src/block.luau:469`).
4. A link the route doesn't claim opens GitHub's own page, so a missing route degrades to the browser.

### The status segment

`window.luau` registers `tern.chrome.status(function(pane) ... end)` (`tern.d.luau:1939`). It returns one `StatusSegment` (`:955-964`) such as "PRs · 2 to review · 10 need fixes", with `command = "plugin.prguide.review"` and `tone = "error"` while flashing.

- **The formatter is O(1).** Tern disables a status hook that takes more than about 4 ms (decoding the 42-PR `hub.cache` there did, and the segment never showed). The formatter reads one module-local `Seen` record (`current` in `window.luau`) and touches no kv. The hub block writes the tiny `hub.status` key beside `hub.cache` on every cache write, and the window's timer reads that key, never the cache.
- **The block can't refresh chrome.** `tern.chrome.refresh` is window only (`:1943`). `window_start` (`:1909`) starts a one-shot window timer that re-arms itself every 2 s (Tern has no block-to-window message, and a `kv.get` is cheap), re-reads `hub.status`, sets `current`, and calls `tern.chrome.refresh()` when `refreshedAt` or `counts` changed. The flash runs 10 s from when the window first sees a new `flashAt` (`Links.watch`), and the window refreshes once more when it ends. The watcher starts from `window_start`, the module load, the first focus and the first status draw, behind one guard. It never calls it from the formatter (that raises, `:1942`).
- **The segment is hidden** (the formatter returns nil) while `hub.status` is missing or malformed (`Links.watch`).

### Timers and visibility

- **Timers.** `tern.timer(ms, fn)` calls `fn` once and returns a `TimerHandle` (`tern.d.luau:1746`) whose `cancel()` has no effect once fired (`:1124-1128`). Every poll is therefore a one-shot that re-arms itself. `src/hub/block.luau` stores each handle in `Block.timers` (`probe`, `refresh`, `checks`, `debounce`, `ring`), cancels the old handle before arming a new one, and sets each delay from `Sync.schedule`. Timers start after `init` returns, as the guide's do (`src/block.luau:697`).
- **Visibility is not observable from a block.** `BlockCx` has `render`, `save`, `exit`, `frame` and `blob`, and no focus, visibility or close hook (`tern.d.luau:1141-1160`); `BlockDef` has no close hook (`:271-291`). Focus and `parked` are readable only in the window half (`FocusEvent` `:1102`, `PaneInfo.parked` `:377`). So **the hub polls for as long as the block exists**, parked or in a background tab, and the "while visible" figures below mean "while the block exists".
- **Focus refresh** comes from the window: `tern.on("focus", ...)` (`:1907`) checks whether the focused pane is a `prguide.hub` block and sends it `cx.session:event(pane, { ev = "action", act = "hub-focused" })` (`:1443`). The block records `focusedAt`, and `schedule` applies the 30 s debounce.
- **Closing the block.** There is no unmount hook, so the block can't be told to stop. Each timer callback first checks `Block.closed`, and a failing `cx:render()` (called under `pcall`) sets it and ends the chain. **[INFERENCE]** that a closed block's `cx:render()` raises. The state issue verifies it: close the hub, then confirm no `gh` process starts for 6 minutes. The shared cache bounds the damage if it doesn't hold: every tick re-reads `hub.cache` and skips a refresh when `refreshedAt` is within the debounce, so a leaked chain costs the free probe, not GraphQL points.
- **Named timers, each with an acceptance check** (the sync issue's `schedule` tests drive them from a fake clock): probe every 60 s, checks every 30 s while a check runs, refresh every 5 min, a 30 s debounce on changes and focus, and a ring that fades after the arrival.

### kv keys and caps

`tern.kv` is a JSON store shared by both halves and every window (`tern.d.luau:1751-1759`). It documents no size limit, so the limits below are our own safety budget **[INFERENCE]**. Reads and writes raise on a bad store, so they sit in `pcall`, as `src/fetch.luau:583` does.

| Key | Holds | Cap |
|---|---|---|
| `hub.filters.<viewer>` | schema 1: repositories, repositoriesEnabled, titleRules and ignoredChecks; personal preferences read and written through Fetch |
| `hub.cache` | `Sync.Cache`, schema 1: normalized records only | at most 50 PRs per search query; the serialized value at most 1 MiB, evicting the oldest `lastActivityAt` first; if the write still fails the block keeps its in-memory state and shows the error |
| `hub.status` | `{ refreshedAt, counts = { toReview, needFixes, flashAt? } }`, written with every `hub.cache` write; what the status segment reads | a few bytes |
| `hub.recent` | `{ Opened }`, migrated from the picker's `recent` key | 8 entries |
| `hub.added` | `Sync.Added`: PRs added by link | 50 entries |
| `hub.prepare` | whether AI guides are prepared in the background (Settings); missing means off | one boolean |
| `hub.preparing` | `{ key = "owner/repo#n@<head>", at }`: the PR a window is preparing a guide for, so another window passes it by; returned when the run ends, ignored after 20 minutes | one |
| `hub.clones` | slug (`owner/repo`) → the clone path the viewer chose ("Choose folder…"), for the agent's clone lookup | one per repo |
| `hub.merge.<owner>/<repo>` | `Sync.MergeRecord`: your choice, what the repo declares, the learned habit, whether you answered the suggestion, `viewerDefault` and when it was checked | one per repo |

Never store raw GraphQL, tokens or diffs. `src/hub/store.luau` reads and writes `hub.cache`, `hub.status` and `hub.added`, `src/hub/lookups.luau` the `hub.merge.*` records, and `src/fetch.luau` `hub.recent`; `hub.clones` is read and written by `src/agent-host.luau` at the clone lookup boundary. The guide's `model` key is `src/agent-host.luau`'s, and `runSeconds` and the retired `recent` keys stay in `src/fetch.luau`, which deletes `recent` after the migration. AGENTS.md's Boundary and Glue lines are amended in the PRs that add `src/github.luau` and `src/hub/block.luau`, so they name those modules next to `src/fetch.luau` and `src/block.luau`.

### Picker retirement

The picker is `src/picker.luau`, `src/view/picker.luau`, and the picker paths in `src/block.luau` and `src/keys.luau`. The hub replaces it, so the one-way-in issue does this in order, in one PR:

1. **Migrate** (everything below has a new home before anything is deleted):
   - the 8-entry recent store (`Picker.openedList`, `remember`, `RECENT_CAP`, `Opened`; `Fetch.recentPrs`, `rememberPr`, `RECENT_KEY`) moves to `Sync` and `hub.recent`. On first load of the hub, a missing `hub.recent` is filled from `recent`, and `recent` is deleted. `Fetch.rememberPr` keeps being called when the guide opens a PR;
   - link and number parsing (`named`, `linkRepo`, `linkHost`, `reference`, `remoteRepo`, `sameRepo`) moves to `src/links.luau`. Its callers are `src/block.luau:590,602,718` and `src/fetch.luau:372,431,439`;
   - `epoch` and `ago` move to `model`; `guideNumbers` (`src/fetch.luau:352`) is deleted with `guidedPrs`, its only caller.
2. **Preserve** in the Review requests fold: ⏎ and a pasted link open the PR, a number alone is refused when it names no repo, and a PR appears once, newest first.
3. **Delete** `src/picker.luau`, `src/view/picker.luau`, `Keys.pickerAction`, `PICKER_ACTIONS`, `pickerKey`, `pickerDispatch`, `showPicker`, `openPicker` and the `picker` field and branches of `src/block.luau`, `Fetch.listAnywhere`, `Fetch.listPrs`, `Fetch.guidedPrs`, and the `gp-pk-*` rules of `guide.css`. A guide block launched with `repo=` and no `pr=` shows "Open a pull request from the PR hub (⌥⌘R)" instead of a picker.
4. **Update** the README, PRODUCT.md and the `docs/screenshots/picker.png` mention in the same change.

### Mockups are references, Tern is the implementation

Product code follows `docs/ui.md:38-40`, not the mockups' CSS.

- **Use:** flexbox (no grid), native `overlay` nodes in `BlockView.layer` (`tern.d.luau:262-269`) for menus, the help panel and confirms, and `cx:toast(level, text, sub)` (`:1133`) for toasts. Tern's `kbd` and `icon` nodes, and `light-dark()` pairs for colors.
- **Don't copy:** `position: absolute` menus, toast and scrim (`index.html:216`, `:319`, `:341`, `:350`, `:398`); `:has()` (`:283`); `rgb(from …)` (`:33`, `:163`, `:199`). Use explicit state classes and fixed `light-dark()` washes instead.
- **No SVG and no grid** appear in the mockups, and the product adds none. `position: sticky` with `backdrop-filter` is for Tern glass only (a nested `backdrop-filter` fails inside the glass header, so menus are overlays).
- **Tokens.** `docs/tern-tokens.css` lacks Tern's `--tk-*` syntax colors, which `review-fix.html` and `pr-fixes.html` copy locally. **#5 adds them to the token file**, and owns DESIGN.md's component and color additions: washed action cards, status chips, the split button, boxes, amber for running CI and purple for agent and Tandem work. #18 adds the agent chip.

### The clipboard

Tern's clipboard is plain text: `cx:copy(text)` (`tern.d.luau:1136-1137`, and `WindowCx` `:1606`). Nothing in `tern.d.luau` takes an HTML flavor. **Copy link** copies `"<title> <url>"` as plain text, and that passes. A rich HTML link through `osascript` in `src/fetch.luau` is optional. If it's added, it needs its own test: paste into a rich-text field and check it keeps the title as a hyperlink.

### Platform constraints

- **Host API:** `tern.timer`, `tern.process.run`, `tern.fetch`, `tern.kv` (`plugin-data/prguide/kv.json`), `tern.fs`, `cx:toast(level, title, body)`, the window-only `tern.chrome` (status-line segments and tab titles), `WindowCx:new_block`. Type definitions: `tern.d.luau` at the repo root.
- **No OS notifications or tab badges for plugins.**
- **CSS:** flexbox only (no grid), `light-dark()`, keyframes, transitions, `position: sticky`. **No SVG:** use text glyphs or Tern's named icons.
- **Page scrolling:** Tern sends a plugin page that scrolls past about 1,100px back to its top when a wheel scroll or a `reveal` overshoots the bottom, and it drops held-key repeats before a block's `key` sees them (checked 2026-10-12). So the board fills the pane (`.gp-hub-fit`) and only its body scrolls; `reveal` and `{ "scroll", Paths.body, "start" }` act on that body. The fixes pages still scroll the page.
- **Untested in Tern:** reduced-motion handling.
- **`luau` has no file or env access** (`io` and `os.getenv` are nil in `/opt/homebrew/bin/luau`, checked). Tests can't read files, so fixtures are `.luau` modules (see Verification).

### What the plugin does today

- **The picker** calls `gh pr list`, `gh search prs --review-requested=@me` / `--author=@me` and `gh pr view` (`src/fetch.luau` around lines 457–501). It keeps the 8 most recently opened PRs in kv. Any pasted PR link opens. The hub replaces it (see Picker retirement).
- **Opening a PR** costs one `gh pr view`. Everything else is local git, fetched into `refs/prguide/<n>/*`. Guides are stored at `<common git dir>/prguide/<n>.json`.
- **Module rules (AGENTS.md):**
  - Only `src/fetch.luau` reaches outside the plugin. The hub adds `src/github.luau` (it starts processes only through the runner `fetch.luau` hands it) and lets `src/hub/store.luau` and `src/hub/lookups.luau` read and write hub kv, except `hub.clones`, which stays at the `src/agent-host.luau` boundary.
  - Only `src/block.luau` does effects, and every action is one `ACTIONS` entry that both clicks and `keys.luau` send. The hub's counterpart is `src/hub/block.luau`.
  - Views live in `src/view/*` and only build nodes.
  - Styles go in `guide.css` with `gp-` classes.
  - A new key goes in `view/help.luau` and the README's Keys table.

## Verification

### Tests

```
tests/run.luau              runs every test module; any failed assert makes it exit non-zero
tests/model_test.luau       tests/links_test.luau     tests/github_test.luau
tests/sync_test.luau        tests/state_test.luau       tests/filter_test.luau     tests/agent_fix_test.luau
tests/fake-runner.luau      a scripted `Github.Runner`
tests/conflicts.sh          the `tools/conflicts` tests: throwaway git repos with conflicts, the five commands run for real (a shell script because `luau` has no process API)
fixtures/hub/…              see the fixture plan
```

```sh
/opt/homebrew/bin/luau tests/run.luau
tools/luau-fixtures --check
tern plugin reload
```

- **Plain `assert`** with literal expected values written independently of the code under test. Each test module returns a function; `run.luau` calls them all, names the one that failed, and rethrows.
- **Pure modules only.** Tests `require` `links`, `model`, `fixes`, `github`, `sync`, `state`, `agent-fix` and `summary`. Never `fetch`, `block`, `window` or a view: `fetch.luau` touches `tern` at load, and the views need Tern's nodes.
- **Frozen clock.** Every rules test passes a fixed `now`, and `cases.luau` records it as `asOf`. No test reads the clock.
- **Specific assertions the early issues must hold:**
  - `model`: every fixture key lands in its expected column and order, including 16 conflict cases (stale, active, draft), and the negatives: a bot's comment, "LGTM", and an approved PR with a leftover thread never make Needs fixes.
  - `github`: `parseHub`, `parseThreads` and `parseChecks` consume the recorded responses. A fake runner asserts that `hub-f` sends no thread authors, that each search pages by cursor up to 50 and halves a page GitHub drops, and that the summed `rateLimit.cost` over a refresh is at most 18 (measured: hub-f 1 a page, threads 5, checks 1). Each call keeps its own envelope; the figure is re-measured after the query changes and updated here.
  - `sync`: `schedule` and `diff` run on a fake clock from 0 to 3600 s. The probe fires at 60 s, a change or focus triggers a refresh within the 30 s debounce, checks poll at 30 s only while a check runs, and the total cost stays at most 220 points.

### Fixture plan

`luau` can't read files, so each recorded JSON has a generated `.luau` twin.

| File | What it is |
|---|---|
| `fixtures/hub/raw-hub-f.json` | A recorded hub-f response holding all three searches, redacted. The fake runner answers every search's page with it (each search reads its own alias); its envelope is a 20-PR page's, 1 point and 2,900 nodes. |
| `fixtures/hub/raw-threads.json` | A recorded `threads.graphql` response, with unresolved threads by people and by bots. |
| `fixtures/hub/raw-checks.json` | A recorded `checks.graphql` response with running, failing and passing PRs. |
| `fixtures/hub/raw-*.luau` | Generated by `tools/luau-fixtures` from the JSON: `return { … }`, with null members dropped as `tern.json.decode` does. Both files are committed. `--check` fails when a twin is stale. |
| `fixtures/hub/agent/*.json` and `*.luau` | Treehouse, `omp` and conflicts-tool transcripts. `tools/luau-fixtures` generates and checks a deterministic Luau twin for every JSON in this directory, using the same rules as the raw fixtures. |
| `fixtures/hub/cases.luau` | Normalized `HubPR` records, `asOf`, the expected column and order per sort, the expected Next up keys, and a `refreshes` list: successive caches with `suppressed`, the expected rings, and the expected toast text (or none). Readable by the CLI and by the fixture block (`fixture=cases`). |

Later issues add their own fixtures (`merge-methods`, `selection`, `details`, `fixes`, `flake`, `rereview`, `agent`, `summary`, `tandem-*`), each with `asOf` where time matters.

**The extended `hub-f.graphql`.** It doesn't select several fields the rules need. Before recording, add `additions`, `deletions`, `changedFiles`, `createdAt`, `baseRefName`, `autoMergeRequest { enabledAt }` and the latest `RemovedFromMergeQueueEvent` (`timelineItems(last: 1, itemTypes: [REMOVED_FROM_MERGE_QUEUE_EVENT])`, with its `reason`). Add a `pullRequest(number:)` alias per PR added by link. **Re-measured** at 11 points and 6–9 s (the table above). The 18-point test limit and the budget hold because `threads.graphql` reads 30 threads per PR (5 points for 17 PRs, not 9). `threads.graphql` and `checks.graphql` gain `id`. Never add thread authors to the search (159 points).

### The fake runner

`tests/fake-runner.luau` builds a `Github.Runner` from a script: each entry matches an argv prefix and returns `{ status, stdout, stderr, timed_out }`. It records every call's argv, `stdin` and `cwd`. An unmatched call fails the test. Every command builder and every `Client` method has a test that asserts the exact argv sent (for example, squash is `gh pr merge <n> --repo <owner/repo> --squash`) and that nothing else ran. No test touches the network.

### Live GitHub actions

- **Only in a disposable repository** named by `GH_HUB_SMOKE_REPO` (for example `you/tern-pr-guide-hub-smoke`), with no branch protection.
- `tools/hub-smoke` seeds it: it opens test PRs (one clean, one behind main, one conflicted, one with a failing workflow) and cleans up by closing them and deleting their branches. It refuses to run without `GH_HUB_SMOKE_REPO`, and every `gh` call it makes passes `--repo "$GH_HUB_SMOKE_REPO"`.
- A tester merges, updates a branch, comments, labels, closes, re-runs and re-requests review **only on cards of that repo**.
- **`post=false` protects review posting only** (`src/block.luau:456,470`, `Prdata.submitReview`). It is not a dry run for merge, update-branch, comment, label, close, re-run or re-request actions.
- Merge methods that need another service (Aviator, a merge queue) are checked against their recorded fixtures, not live.

### UI checklist

Run it against the fixture block (**New PR hub sample block**, `fixture=cases`, a frozen clock, no network). Repeat every row in **light and dark** (switch Tern's theme), at two sizes:

| Size | Hub |
|---|---|
| Wide | the window at 1440 × 900, the hub alone in its tab |
| Split | the hub pane 720 px wide beside a terminal (`index.html:23` uses 720 px) |

Record `cx.cols` and `cx.rows` (`tern.d.luau:1146-1149`) with each run. Save screenshots to `/tmp/hub-checks/` as `hub-<light|dark>-<wide|split>-<step>.png`.

| # | Do | Expect |
|---|---|---|
| 1 | `⌥⌘R` | One hub opens. Press `⌥⌘R` again: no second pane, the hub is focused. Park the hub, `⌥⌘R`: it comes back. Focus another pane, `⌥⌘R`: it is focused again. `⌥⇧⌘R` with a hub open: still one, and its ⏎ now starts the AI guide. |
| 2 | `T`, `T` | The tab switches and switches back. Blue counts show only your-turn cards. |
| 3 | `/`, type, Esc | Focus enters the search field and the list filters. `j` types into it. Esc clears it and returns to the board. |
| 4 | `F` | The repository menu opens without animation: `j`/`k` move, Space toggles, ⏎ or Esc closes. |
| 5 | `S`, each of the five sorts | The order matches `cases.luau` for that sort, including Smallest first. |
| 6 | `h j k l` and the arrows | Up and down stay in a column; left and right go to the nearest card in the next column. **No card changes height** when selected or hovered, with six or more long titles and a mix of draft and stale cards (compare the card's top-to-next-top distance before and after). |
| 7 | `?`, then Esc | The grouped shortcut panel opens, and Esc closes it. A click outside also closes it. |
| 8 | `.` repeatedly | Next up visits the keys in `cases.luau`'s Next up list, switches tabs when needed, shows "n of N", and ends hidden when nothing needs you. The cursor never moves on open. |
| 9 | `⌘R` in the fixture block, once per `refreshes` entry | First load: no ring, no toast. A merge-failed arrival: red ring, segment flash, toast "#396 needs fixes: merge failed". Three arrivals: one toast "3 pull requests need fixes". A conflict-only arrival: ring, no toast. An inactive PR: nothing. A PR the viewer just merged or fixed: nothing. A PR that became ready: green wash, no toast. |
| 10 | `⌥⌘R` twice more, then close the hub | The status segment shows the counts, flashes red on an arrival, and its click focuses the hub. After closing, no polling continues (see Timers). |

### Per-PR gates

Every PR passes these before review:

1. `/opt/homebrew/bin/luau tests/run.luau` and `tools/luau-fixtures --check` exit 0.
2. `tern plugin reload` exits 0 and loads both `prguide.guide` and `prguide.hub`.
3. The UI-checklist rows the PR touches pass in light and dark, wide and split, and the screenshots are attached.
4. A PR with live GitHub actions has them tried in `GH_HUB_SMOKE_REPO`, nowhere else.
5. `GUIDE.md`, `prompts/explain.md`, `prompts/review.md` and `src/guide.luau` still change together when the guide changes; a new key is in `view/help.luau` and the README Keys table.

## How to build this

- **Base.** Branch every issue from `docs/pr-hub-design` and open its PR against that branch. **One PR per issue**, and the issue's `Touches only` list is the PR's file list. A PR opens only after every issue it depends on has merged, and it rebases onto the branch first.
- **Commits.** Each subject is the user-visible behavior as a plain sentence, with no type prefix (AGENTS.md, Commits).
- **Shared files.** No two issues edit the same shared file at once. The files are `src/hub/block.luau`, `src/hub/state.luau`, `src/hub/model.luau`, `src/github.luau`, `src/fetch.luau`, `src/keys.luau`, `src/view/hub/`, `guide.css`, `AGENTS.md` and `tests/run.luau`. The order below is the serialization: a later issue builds on the earlier one's merged contract, and changes a contract here first. The one allowed overlap is #3 and #5, which each append lines to `tests/run.luau` and `AGENTS.md`; the second to merge rebases onto the first.
- **Issue #15 ownership exception.** Its `Touches only` list omits shared verification files that its Done when criteria require. #15 registers `agent_fix_test` in `tests/run.luau`, extends `tools/luau-fixtures` to generate and check `fixtures/hub/agent/*.luau` from every JSON in that directory, and records these decisions here. `hub.clones` is read and written by `src/agent-host.luau` so clone lookup stays at the boundary. The public `AgentFixRun` contract signatures stay unchanged.
- **Issue #18 acceptance exception and settled details.** Its acceptance criteria also permit the README Keys table, registration of `agent_state_test` in `tests/run.luau`, and this paragraph. A on a running card means Stop; A attempting a different fix while a run, lookup or lease return is active says exactly "One fix at a time". Existing feedback-only Summarize and flaky-check priorities remain until their owning issues change them. Clone repo selects a parent folder and clones to `parent/repo-name`; Choose folder selects an existing clone, remembers it through `AgentHost.rememberAgentClone`, then revalidates through `AgentHost.findAgentClone`. With no host folder picker in the documented block API, Block uses `Fetch.runner` with macOS `osascript`; cancellation returns to No local clone without an error toast. Open worktree uses the same runner to open the failed worktree in Finder. `HubPR` omits the head branch name, so Block reads `headRefName`, `baseRefName` and `headRefOid` with a read-only `gh pr view` through Fetch.runner and checks them against the card before starting. `fixture=agent-cards` shows all lifecycle states without lookup, dialogs or processes; ⌘R advances the running card by one #15 transcript event, A stops it, then A on another card starts a new recorded run. A ready fixture remains in place. #16 owns all Review, Discard and Push actions; this issue displays the ready commit and complete path only. UI checklist screenshots and execution evidence are owned by the parent integration round.
- **Issue #16 acceptance exception and settled decisions.** In addition to its primary file lane, #16 edits only `guide.css` for the new view, `src/view/hub/help.luau` and `README.md` for keys and behavior, `tests/run.luau` for registration, and this spec for contracts and scope. The hand-written `fixtures/hub/review-fix.luau` is not generated. `fixture=review-fix` supplies two files, three unique hunks, every provenance tag, and a take-both rule; fixture Push/Discard simulate outcomes with no processes or network. Enter and double-click use the existing `hub-open` action to open Review fix from a Fix ready card, retaining #18's tested empty primary action slot. Needs fixes still opens the existing fixes page. The mockup's dropped rows and Other changes fold are omitted because acceptance requires only conflict resolutions; original sides appear in one horizontally scrolling excerpt with ownership badges, using the existing flexbox code rows. No new motion is added; the page omits `gp-soft` and suppresses inherited button transforms/transitions. Original snapshots remain available on B if commit verification fails. Commit verification is conservative: changed or non-unique context locks Push. Ready state retains its reviewed ids, verified excerpt and completion marker on any push/return failure; P retries cleanup after push success, and D asks again after a failed discard return. `AgentFlight` and its exact engine stay held until return is proved successful. The fake-runner acceptance lives in the pure planner and injected runner/lease simulation in `review_fix_test`, while Fetch executes the validated plan. Tests, reload, screenshots, light/dark wide/split checks and the live push in `GH_HUB_SMOKE_REPO` are deferred to the parent as instructed; this implementation run performs none of them.
- **Issue #19 integration exception and settled details.** In addition to its `Touches only` list, #19 edits `tests/run.luau` (registers `summary_test`), the `tests/state_test.luau` and `tests/flake_test.luau` assertions its rule supersedes, and this spec. A correction round adds one documented scope exception, because bot review bodies and current requested changes cannot be read otherwise: `src/github.luau` (`DETAILS_QUERY` and `parseDetails` only), `docs/hub/queries/details.graphql`, focused query and parser regressions in `tests/github_test.luau`, and `fixtures/hub/summary.luau`.
  - **Actions.** A is Summarize only when `Summary.onlyComments(Summary.current(details, pr))` holds for the loaded details, or, before details load, when no live human review requests changes; otherwise A is Fix with agent and ⇧A is Summarize. Fix bot comments and Summarize appear on an In review card with a bot feedback source: an unresolved bot thread, a bot review that requested changes, or a bot comment review at the current head (`State.botActionable`).
  - **Current feedback.** `Summary.current` filters the cached details against the board's `latest` reviews before `onlyComments`, the summary prompt and the bot input. A requested-changes review counts only while its author's latest review still requests changes at the current head (the newest per author); a thread of an author who no longer does is a plain comment. A bot's review-level comment counts only while that bot's latest review is a comment at the head.
  - **Bot comment reviews.** `details.graphql` adds `commentReviews: reviews(last: 20, states: [COMMENTED])`. `parseDetails` keeps only an author whose `__typename` is `Bot`, their newest comment review, at the head, with a nonempty body that no inline thread by them repeats. It is carried as a `ThreadDetail` with `id = "review:" .. url`, no path and `bot = true`, so the fixes page lists it only under "Not counted". A person's comment review is never read as a requested change. Cost stays 1 point (requests, not nodes).
  - **Stale feedback.** Summarize and Fix bot comments read the details live for every press (a fixture board reads its recorded sample). A read or answer is dropped when the board's `State.feedbackSignature` for the PR changed while it was out. `State.replace` drops a summary, and details unless that PR's page is open, whenever the signature changes with the head unchanged. Summaries are never saved.
  - **Block regression harness.** `tests/summary_test.luau` loads the real `src/hub/block.luau` and `AgentHost.summarizeFeedback` with the fields of `src/host.luau` stubbed, `Fetch.runner`, `findRepo`, `AgentHost.findAgentClone` and `AgentHost.startAgentFix` replaced, and the board's GitHub client given a counting `details`. Every effect is a recorded callback the scenario settles by hand: a bot feedback signature or prompt changed while the refs were out, a comment edited or the second read failing while a summary ran, a timeout, an error exit, a thrown spawn, a closed block, a failed render and duplicate callbacks, each asserting the card state, busy state, toasts and draw count. Removing the post-refs comparison or the summary's second read ends a scenario in the wrong state.
  - **Summary command.** `Summary.plan` is the only way to a command: an `omp` executable, a model selector that cannot read as an option, a known thinking level and a prompt that starts with the module's fixed line, so the final argument is never an option or an `@file` attachment. `AgentHost.summarizeFeedback` takes the agent and the prompt, calls `plan` and fails closed on nil.
  - **Bot worker confinement.** OMP documents `--add-dir` as extra workspace, not as write confinement, and its tools take absolute paths, so the worker is not trusted to stay in its worktree. `AgentFix.sandboxProfile` builds a Seatbelt profile and the engine runs `/usr/bin/sandbox-exec -p <profile> /usr/bin/env XDG_STATE_HOME=<worktree>/.prguide-omp-state omp …`: reads, network and processes stay open; every write is refused except under the leased worktree (its `.git` pointer, matched by `literal` and `subpath`, excluded) and the `/dev/null`, `/dev/tty` and `/dev/dtracehelper` nodes. Neither `~/.omp` nor any temp folder is writable, and `~/.omp` is denied by name, so a prompt-injected tool call cannot write OMP's configuration, extensions or skills, or another process's temp files. A /tmp, /var or /etc path is also listed under its resolved `/private` path, since the kernel matches resolved paths. Without `spec.sandbox`, a path that cannot be quoted, or a missing `sandbox-exec`, the run fails before or at the agent step and returns the lease. OMP creates its run state before any model call, which the `~/.omp` denial would refuse, so only `XDG_STATE_HOME` is redirected to a reserved folder inside the worktree; `XDG_DATA_HOME` is left alone because OMP keeps its credentials there, and the profile is unchanged. The engine sets the folder up with exact injected commands and no shell: `git ls-files -- .prguide-omp-state` must be empty (a tracked path fails the run), then `/bin/mkdir <root>` and `/bin/mkdir <root>/omp`, both without `-p` so an existing file, folder or link at that path fails closed and is never removed. The OMP step keeps its 20-minute timeout. `/bin/rm -rf <root>` then removes exactly that path, which this run created and only if it did, before the OMP result is read and before any `git add` or diff, so on success, failure, throw, timeout and Stop alike no runtime file is staged or left behind. `rm -rf` unlinks a link without following it, so a link swapped in by the worker is removed, not its target. Stop waits for the OMP callback, cleans, then returns the lease. A setup, OMP or cleanup failure fails the run and returns the lease; if the folder could not be removed, the lease's `reset --hard` and `clean -fd` still run before the return. If OMP cannot run under this write boundary, the agent step fails and the lease returns; nothing is applied. The conflict workflow is unchanged.
  - **Bot worker on Windows.** Windows has no sandbox the plugin can apply, so there `AgentHost.startAgentFix` sets `Spec.unconfined` instead of `Spec.sandbox`, and the engine runs the same `omp` argv straight in the worktree, with no state folder. Only its tools (`read,edit,write,grep,glob`, no shell) and its prompt keep it in the worktree; the review page still shows every line it changed before anything is pushed. A spec with neither field still fails closed.
- **Issue #20 acceptance exception and settled details.** In addition to its `Touches only` list, #20 edits `src/hub/state.luau` for these and nothing else: in `actionsFor`, the In review branch (Hand off to Tandem first on a watched card, and no new Merge when ready); in `toCard`, the `agentSlot` flag and the failed-card projection (a watched card offers Hand off to Tandem, and Return worktree while the lease is held, instead of Try again); the `AgentFixState` failed variant, which gains `held: boolean?`; `agentFailed`, which takes `held`; `agentFlight`, which reconciles `held` with the engine's lease along with the path; and the lifecycle `dropObsoleteAgents`, which `State.project` runs first and which drops a no_clone state, or a failed state with no worktree, on a watched PR, since neither starts anything any more. `tests/run.luau` (registers `tandem_test`), `tests/sync_test.luau` (only the Needs fixes count in the merge test, which the placement rule below changes from 2 to 1), `src/view/hub/help.luau` and `README.md` (only the A and ⇧A entries in the help panel and the README Keys table: A must also name Hand off to Tandem, and ⇧A must also name Return worktree, the contextual ⇧A action on a watched card whose failed fix still holds its lease, because a new control is documented in the same change) and this spec. Without the state edit the acceptance cannot be reached: Needs fixes is the only column that offered Hand off to Tandem, and a watched PR with fix reasons must stay In review. Model placement puts every live, non-draft PR of the viewer that Tandem watches in In review with empty `reasons`, before the Needs fixes and Ready rules, so a watched PR that could merge is not in Ready and offers no merge; drafts, Inactive PRs and review-role PRs keep their places. An In review card Tandem watches offers `card-handoff` ("Hand off to Tandem", A) first and Copy link behind it, with the chip Waiting on Tandem, and never Fix with agent, Fix bot comments, Summarize or an agent slot; `card-agent` also refuses a watched PR. The fixes page keeps using `State.fixMain`, so it shows the same label. `Model.parseTandemWatch` turns the decoded `tandem watch --json` into a set of lowercase `owner/repo#123` keys (a row with color `unwatched`, or one that is malformed, is left out; a document that is not the output is nil) and `Model.tandemFlags` turns that set into flags by the board's own keys, because Tandem's spelling of a repo can differ in case. The block reads Tandem on open and at the start of every refresh, in the repository root (the block finds it from `cx.cwd`, which may be a subfolder, with `Fetch.findRepo`, once per block, and shares that one lookup between the read and any hand-off waiting for it; a root that cannot be found is not kept, so the next call looks again), one read at a time; a failed or unreadable read, no `cx.cwd`, or no root changes no flag (every flag is false until a first good read). `Tandem.watch` runs exactly `tandem watch --json`. `Tandem.handoff` runs exactly `tandem native act` with stdin `{ v: 1, origin: { plugin: "prguide", repoPath: ROOT }, action: { verb: "pr-fix", repo, number, reason } }` and nothing else; a non-zero exit, a timeout, malformed output or a throw is an error, and the callback settles once. `reason` is `Model.handoffReason`, the card's fix reasons in words ("PR hub: failing checks, merge conflicts") or "Hand off from the PR hub". Both calls run in that root and `repoPath` is that root, never the raw `cx.cwd`. Nothing is sent before A or a click on the card's action; with no root, the press shows "Couldn't hand off to Tandem: …" and sends nothing, and a card that is gone or whose head moved while the root was being found is sent nothing. `done` and `kept` set only that PR's `tandem` flag (and the block's watched set, so a refresh keeps it), and `kept` shows Tandem's notice as an info toast; `refused` shows the notice text as an error toast and changes nothing. An answer is dropped when the card is gone, its head moved, or the block closed. A read of Tandem that began before a `done` or `kept` hand-off is dropped when it returns and a new read starts, so a hand-off is never undone by an older snapshot; the cache's PRs and its Needs fixes and To review counts (over every PR, `flashAt` unchanged) are recounted whenever Tandem's flags move a PR. No agent fix starts, retries or looks for a clone on a watched PR (`beginAgent` refuses it, and every delayed step re-checks before the engine starts); a fix still being set up when Tandem takes the PR ends as stopped, and Stop, Retry's lease return and Open worktree still work. Ownership from another window's cache joins this block's set, and the other window's silence never clears one: only a successful read of Tandem here does, whatever the cache's age, and a read that began before the join is dropped and read again. Joining and adopting have different rules. A cache is adopted whole only when its `refreshedAt` is strictly newer than this block's. Its flagged PRs join when its `refreshedAt` is the same or newer, never older, because a hand-off persists the cache's flags without changing `refreshedAt`, so two windows that opened from the same cache share a stamp after one of them hands off. The join also happens at two more points. When a GitHub refresh answers, before the answer is merged and persisted, the shared cache is read and its flagged PRs join the set and the epoch moves, so a delayed refresh cannot overwrite the other window's ownership with a cache built from an older set. When a read of Tandem answers, the shared cache is read and joined before the answer is checked against the epoch or applied; if that join moved the epoch the answer is dropped and read again, so an older read that returns before the GitHub refresh cannot overwrite a newer cache's ownership either. An older cache joins nothing. Joined ownership guards the card at once: it is set on the board's PRs and recounted (a fix still being set up ends as stopped, and the card drops Fix with agent and Merge when ready) before the read that is read again, or the refresh, answers, and the dropped read stores nothing. Every local write that is not a read of Tandem (an action's cache update, a checks update) joins first, so it never stores another window's flag as false, and it never lowers the shared `refreshedAt`: when the stored cache is strictly newer than this block's, that cache becomes the board first (its ownership joins) and only the action's own change (`keepCache`'s `edit`) or the check results are applied to it, so an older window's whole snapshot is never written over newer data and never relabelled with the newer stamp. A checks result for a PR whose head the newer cache moved is skipped like any moved head. `card-update` sends nothing for a card Tandem watches, so an Update branch queued before the ownership arrived does not run. Ownership another window stored does not wait for this window's own read or refresh to answer: before every action's handler (`dispatch`), at every delayed step of a fix's setup (`carryOn`), before each merge of a batch (`runMerge`) and at every `canPush` check, the block reads the shared cache and joins its flagged PRs when its `refreshedAt` is the same or newer, never older. The join is positive only, sets the flags on the board's PRs and recounts, and persists nothing; a fix still being set up then ends as stopped, a running engine is never stopped by it, and a sample board skips it. A ready fix never pushes to a watched branch: the push is refused before it starts and `canPush` (checked before every command of the push, so ownership that arrives during its remote reads stops it) refuses once Tandem watches the PR, keeping the ready fix and its lease for Discard; a push that already went out still ends in its lease return. A failed lease return on a watched card (a failed state whose engine still holds the lease) offers **Return worktree** (⇧A, free on that card) behind Hand off to Tandem: it is `card-agent-retry` acting as cleanup only, returns the lease through the retained engine and never starts a fixer. The engine's `held()` is the truth about the lease, and it can be held before the engine has sent any worktree event (it takes the lease, then verifies the path), so a failure can carry no path. `dropObsoleteAgents` would drop that failed state on a watched card, so the block keeps the failure reason on its flight and, whenever it reconciles the flight with the engine (`forgetReturned`, which runs after every settled outcome and again once the engine handle is returned), puts a failed state back from `held()` if the lease is held, the flight has settled, and no state remains. That covers a failure that arrives after the handle exists and one that arrives synchronously inside `AgentHost.startAgentFix`, before it returns the handle. Nothing clears or retries a held lease on its own: only a successful guarded return does, and a failed one leaves Return worktree in place. A watched card offers no Merge when ready (any method) and `card-merge`, `card-auto` and a stale confirm send nothing for it; Cancel merge stays for a merge already pending. `fixture=` boards parse `fixtures/hub/raw-tandem-watch.json` at open and flag every board they show, including each ⌘R step, without a process; the recorded PR lists are copied, never edited, and the sample board's A on a watched card only shows an info toast. `fixtures/hub/raw-tandem-pr-fix.json` records a success, a kept and a refusal outcome. `tests/tandem_test.luau` stubs the fields of `src/host.luau` and `Fetch.findRepo`, and settles every recorded call by hand. Every write of `hub.cache` carries a `writeId` (this window's nonce and a count), so a stored cache is told apart from another stored at the same `refreshedAt` without touching GitHub's freshness; a cache written before ids existed reads as id "". A successful read of Tandem that clears a flag and whose save fails shows the usual "the cache couldn't be saved" error and keeps its memory state, and the block retires the `writeId` of the cache the store held when the answer arrived: it is read once, before the answer is applied, adopted or joined against anything, and the failed save retires that captured id and never rereads the store. While a successful read of Tandem applies its answer, adopting a strictly newer cache writes nothing and marks the ownership it restores as unsaved, so the answer's save is the only local write on that path and no intermediate cache is left to revive a cleared flag. An answer that is dropped as stale, or that fails closed because the store cannot be read, or a failed read, writes nothing at all; the mark waits for the next successful, non-stale answer, which stores it once even when it changes no flag, or for any other write of the cache. `sharedCache` ignores a cache carrying a retired id, so that superseded cache cannot bring the cleared flag back through a dispatch, a setup step or a refresh. Any later write has a new id, so another window's hand-off stored after the clear, even at the same stamp and even while the failed save is in flight, still joins and blocks effects. The retired set is in memory only and nothing waits on it. If the store holds no valid cache when the answer arrives, nothing is retired. If the store cannot be read at all, a clear fails closed: the answer changes no flag and stores nothing, and the next read of Tandem decides again. A cache without an id can only be the superseded one or a pre-id write, so a retired "" ignores both. A closed block sends nothing more: `runMerge` submits no command, and a batch's step, its finish and its toast do not run, once a draw (for example the one that shows adopted ownership) has closed the block. A join that draws a card and raises (the block is gone) leaves no flight, and `carryOn` then answers false, so a lookup that was out cannot go on to start an engine. Tests, reload, the UI checklist in light and dark (wide and split) and the live hand-off in `GH_HUB_SMOKE_REPO` belong to the parent.
- **Order:**
  1. **v0.** #2 (rules, fixtures, test runner) → #3 (GitHub data) and #5 (board, built against `fixture=cases`) in parallel → #4 (sync) → #6, #7, #8 in that order.
  2. **v1.** #9 → #10 → #12 → #11 → #13 → #14. #10 comes before #11 and #14, and #12 before #13 and every later consumer of the details contract.
  3. **v2.** #15 (agent engine) → #18 (agent card lifecycle) → #16 (Review fix, Push and Discard) → #19 (Fix bot comments and Summarize) → #20 (Tandem hand-off). The Tandem PR is a separate PR in the Tandem repo, so it can be built any time, but **it must merge before #20's plugin side**.
- **The Tandem PR.** It goes in https://github.com/jdeocampo99/tandem as its own PR, based on `main`, and adds the native verb `pr-fix` (see Tandem below).

## Tandem (we own it)

- **pr-watch** (`src/pr-watch/`, state in `~/.tandem/state.sqlite`) polls GitHub through gh every 1–5 min. It doesn't see review requests or the need to re-review.
- **"Waiting on Tandem"** comes from `tandem watch [PR] --json`.
- **Handing off a PR needs a new verb.** `tandem native act` only accepts a coordinator's own pane (`src/native/actions.ts:175-258`), so a hub request would be refused. Add a verb such as `pr-fix {repo, number, reason}` with a plugin origin rule, mapped onto the existing `pr-watch-fix` tool (`src/session/tools.ts:357-369`).
- **The Tandem PR** is separate, in https://github.com/jdeocampo99/tandem on its default branch `main`, and merges before the plugin side of the hand-off. Native verb `pr-fix`: request `{ repo: string, number: number, reason: string }`, response matching the native outcome `{ status: "done" | "kept" | "refused", notice?: { code: string, text: string } }` (merged as jubbydev/tandem#438; a refusal can still exit 0). It accepts the plugin's origin and refuses any other, maps onto `pr-watch-fix`, and ships fixtures for success and refusal. "Waiting on Tandem" shows after `done`.
- **Worktrees** come from treehouse, from Tandem's pool:
  - acquire: `treehouse --root ROOT get --lease --lease-holder prguide --no-fetch --json` (cwd is the repo's clone);
  - return: `treehouse --root ROOT return PATH --if-lease-holder prguide --if-lease-id ID`;
  - root: `TANDEM_POOL_ROOT`, else `~/.tandem/pool`.
- **Clone lookup:** Tandem's `repo_locations` table (`src/repos/locate.ts:39-61`), or the plugin's own map in kv when Tandem isn't installed. A missing repo is cloned with `gh repo clone owner/repo DEST -- --filter=blob:none --no-checkout`, after asking once.
- **Tandem's conflict fixing** hands the whole job to an AI (`src/pr-watch/watcher.ts:731-737`). It should adopt the token-light pipeline above.

## Build plan

Ship in stages that each work end to end. Each stage is a commit series that `tern plugin reload` accepts and that can be tried with a real PR opened with `post=false`.

| Stage | Scope | Why this order |
|---|---|---|
| **v0: the board** | Data layer (a `HubPR` record, kv cache, hub-f + threads + checks queries, `/notifications` probe, the poller); both tabs and their columns; filter, sort (including Smallest first), search; h j k l; ⏎ opens the existing review view; Copy link; Merge for the three GitHub methods with ⌘⏎; add by link; arrival ring, status-line segment and toast; one way in (⌥⌘R opens or focuses the hub, the status-line segment opens it, Recently opened becomes a fold); sizes on review cards | Read-mostly and low-risk. It replaces the picker as the daily entry point and proves the cost and polling plan. |
| **v1: less hunting** | The fixes page (⏎ on Needs fixes); per-repo merge methods (declared, learned, comment, label, queue) and Merge failed; Summarize; the friction items below marked v1 | Each item turns "open GitHub and find it" into one key. No writes beyond comments, labels and merges. |
| **v2: agent work** | Fix with agent, Fix bot comments, Review fix, Push; treehouse; clone lookup; the `conflicts` tool; the Tandem `pr-fix` verb | The largest, and it writes code and pushes, so it builds on a trusted v0 and v1. |

**Build checks:**
- `tern plugin reload` exits 1 if the plugin fails to load.
- Check UI in light and dark.
- `GUIDE.md`, `prompts/explain.md`, `prompts/review.md` and `src/guide.luau` change together.

## Open questions

- **Queue position:** "2nd in line" needs the merge tool's own API (Aviator's sticky comment, or a token). Without it, the card says "waiting for the merge".
- **Copy link:** plain "title url" is the acceptance. A rich HTML link through `osascript` is optional and, if added, must be tested.
- **DESIGN.md additions** are owned by #5, together with the `--tk-*` syntax tokens in `docs/tern-tokens.css`. Confirm amber for running CI and purple for agent and Tandem work before adding them. The Components section should document washed action cards, status chips, the split button and boxes. #18 adds the agent chip.
- **`pr-fixes.html` wording (settled in #12):** the page takes the card's own main action from `State.fixMain`, so a Tandem repo says "Hand off to Tandem" and a comments-only card says "Summarize"; the buttons send the card's action.

## Friction backlog

All rows are approved by the user; ideas the user didn't pick were dropped. Each item turns a trip to GitHub, or a return visit, into one key.

| # | Idea | Stage | Design |
|---|---|---|---|
| 1 | **Next up** | v1 | **A banner above the board** (chosen): one quiet gray line, sized to its content and left-aligned, reading left to right: Next up · the item's chip · its title · "web #412 · 11 left" · **Go** [.]. It walks everything that needs you across both tabs, most urgent first; `.` or a click goes to the next item, switching tabs when needed. The hub never moves the cursor on open (an automatic jump felt random). The count becomes your position while walking ("2 of 11"). In split view the repo and count drop out. Hidden when nothing needs you. Rejected: a blue control in the tab row, a label in the hint bar, a header button, and a count beside the title (`nextv=header\|title` keep them for comparison). |
| 2 | **Re-run failed checks** | v1 | Behind Fix checks ▾ for every failing check. Moves first, with the label "Likely flaky", only when the evidence says so (see below). Never re-runs on its own. Each CI module re-runs its own checks (`gh run rerun <id> --failed`, `bk job retry <job>`); zero tokens. |
| 3 | **Update branch** | v0 | A Ready card whose branch is behind main (`mergeStateStatus == BEHIND`, no conflicts) shows "Behind main" and **Update branch** (U) as its main action, because strict branch protection blocks the merge until then. `gh pr update-branch`; zero tokens. The card then waits for checks in In review. |
| 4 | **Merge when ready** | v1 | Behind the ▾ on In review cards. Once set, the card shows "Merges when ready" and needs nothing more. Uses `gh pr merge --auto` (needs the repo's "Allow auto-merge" setting; hidden when it's off), or, for comment-based repos, the merge command posted early (Aviator accepts `/aviator merge` while a PR is still pending). |
| 5 | **Re-request review** | v1 | Driven by state, not a toast: when a reviewer's latest review requested changes and you've pushed since, the In review card reads "Waiting on @maria-k to re-review", and its main action is **Re-request review** (`gh pr edit --add-reviewer`). |
| 7 | **Size and Smallest first** | v0 | +84 −12 on review cards, and a "Smallest first" sort. The current hub-f query doesn't fetch `additions` and `deletions`: #3 adds them (see Verification). |
| 8 | **Merge several** | v1 | Space marks cards (as in file managers); M then merges the marked ones in queue order, after one confirm that lists them. Each uses its repo's merge method. |
| 9 | **Close stale PRs** | v1 | Space selects cards in Inactive, and **Close stale** (⇧X) in the fold header selects every stale PR but skips drafts (drafts are deliberate work in progress, so only Space selects them). One confirm lists them. No closing comment by default. `gh pr close`. |
| 10 | **One way in** | v0 | See below. |

**Mocked in `index.html`:** Next up (1), Update branch (3, on #181), Merge several (8) and Close stale (9).
- **Next up:** the tab-row control described in row 1.
- **Selecting:** Space or ⌘/⇧-click selects; Esc clears. A selected card gets a blue wash, with a blue box in place of its gutter check.
- **Decisions (#11).** `State.confirm.kind` also takes `"batch-merge"` and `"batch-close"` (`keys` = the marked cards in column order); `State.selection(s)` builds the bar and its confirm (`Selection`, `BatchConfirm`). Marks last while the card stays selectable, in this tab, matching the filter and (Inactive) shown. M and X act only while something is marked; Esc clears the marks first. The batch confirm is a native overlay in the layer (anchored to the bar, scrim click cancels), because Tern ignores `reveal` for nodes this far down; the inline bar stays in the column. A batch runs one PR at a time, each with `s.merges[repo]` as resolved (a learned, unconfirmed comment is used as shown in the confirm), stops at the first failure, leaves the rest marked, and ends in one toast. `⌘`/`⇧`-click arrives as `ev.mods` on the `hub-open` action and becomes `hub-mark`.
- **The selection bar** sits at the top of Ready to merge (or inside Inactive): "2 selected · Merge 2 (M) · Clear (Esc)".
- **The confirm** lists at most 5 titles plus "and N more", then one line on how they merge (for example "Comments /merge"), or "Closed pull requests can be reopened."
- **Only mergeable cards can be selected:** a card that's behind main or already queued can't be.
-

**Flake evidence (friction item 2, issue #13).** All checks are cheap, and the results are cached per repo:
- **History:** the same check (name and workflow) failed on recent main commits without a fix in between, for example "failed 3 of the last 20 runs on main". **3 or more failures in the last 20 runs on main means likely flaky, and 1 or fewer means not**; two is not enough alone. Fetched per repo about hourly from the Actions runs API.
- **Same code, different result:** the check passed on an earlier run of this same commit, or on the previous commit when the new commit didn't touch the failing area.
- **Failure text:** timeouts, network resets, rate limits, a lost runner, out-of-memory (exit 137) mean infrastructure, not code.
- **Annotations outside the diff:** the errors point only at files the PR didn't change.
- **Decisions (#13).** History is keyed by workflow name (the runs API has no job names), counting the workflow's newest 20 finished runs on the base branch; cancelled and skipped runs count for nothing. "Passed earlier" is a successful run of the same workflow on the same commit (a push run beside the failing pull-request run); the "previous commit without a change to the failing area" variant is not read, because it needs a diff per commit. Failure text is the check's summary and every annotation (the runner's exit-code lines included). The verdict is per card: flaky only when every failing check with a workflow run is. The block reads evidence for up to 10 Needs fixes cards with a failing check after each refresh (the details call, the hourly history, one runs call), in memory only. Re-run failed checks is ⇧R (`R` is Recently opened on the board and Reply on the fixes page) and sends `gh run rerun <id> --failed --repo <r>` once per distinct run; it moves first on the card only when the card's sole reason is the checks.
- The card says why: "Likely flaky: failed 3 of the last 20 runs on main". When an annotation points at a changed file, the failure is treated as real and **Fix with agent** stays first.

**One way in (friction item 10, issue #6).** Today the palette has "New PR review block" (⌥⌘R) and "New AI generated PR review block" (⌥⇧⌘R), each opening a picker (`window.luau:11-12`, via `tern.command`). The hub replaces the picker:
- **⌥⌘R opens the hub**, or focuses it if one is already open, so there's one hub per window. Picking a PR is just ⏎ on its card, and pasting a link is the To review field. Two entry points to the same list would be clutter.
- **⌥⇧⌘R** opens the hub too, but ⏎ there opens the PR with the AI guide started. On any card, ⇧⏎ does the same.
- **The status-line segment** ("PRs · 2 to review · 10 need fixes") runs the same command on click. `StatusSegment.command` takes `plugin.prguide.<id>`.
- **The picker's "Recently opened"** (PRs you opened from any repo) moves to a fold under Review requests, so a closed PR stays one key away.

Proposals rejected so far: automatic pushes, "Fix all", toasts for conflicts, and automatic re-runs.

## Mockup reference

**Files** (in `docs/hub/mockups/`):
- `index.html`: the hub. Variant F is the approved one; G and H are kept for comparison.
- `pr-fixes.html`: the fixes page.
- `review-fix.html`: the Review fix page.
- GitHub query research is in `docs/hub/queries/`: `hub-f.graphql`, `threads.graphql`, `checks.graphql`, `probe.graphql` and a redacted `sample.json`.

**index.html URL params:**

| Param | Effect |
|---|---|
| `t=dark\|light` | Theme |
| `w=wide\|split` | Width |
| `tab=mine\|rev` | Starting tab |
| `agent=1` | Seeds the agent states: #169 running, #177 fix ready, #174 failed, #77 no local copy, #404 summarized |
| `sel=<repo>%23<n>` | Selects a card |
| `confirm=1` | Opens the merge confirm |
| `sort=` | Starting sort |
| `repos=` | Starting repository filter |
| `menu=repo\|sort\|agent` | Opens a menu |
| `act=below\|bar` | The rejected button placements, for comparison |

**Mock bar:** demos for checks passing, approval, an agent fix, and a merge failing, plus a link to the Review fix page.

**Sample merge settings:** acme/web is declared Aviator, Tagalingo-App has a learned `/merge` (not yet confirmed), tern-pr-guide rebases, and every other repo squashes.

**Other pages:**
- `pr-fixes.html`: `pr=58|404|418`, `t=`, `cur=`, `focus=panel`, `bot=1`, `reply=1`, `noann=1`.
- `review-fix.html`: `t=`, `cur=1`, `rv=1`, `orig=1`, `ask=1`, `open=1`.

## Design history (why it looks like this)

- **A–E (lists and sections, including E3)** were replaced by F. Your PRs and your review queue are different processes, so tabs stop them competing for attention.
- **Button placement:** "buttons below the selected card" made cards jump and hid what each card needed. "Buttons at the top right" crowded the chip line and overflowed with long status chips. The final rule is the hover/selection swap on the repo line.
- **"Paste a link" in search** was ambiguous, so To review got its own field.
- **Hard-coded Aviator support** became the general per-repo merge method.

## User preferences

- Very short replies; screenshots for UI work.
- UI copy is neutral and official, like GitHub. Every label says what's needed from the user. No filler copy.
- Keyboard first, with vim keys.
- Push back when you disagree.

## Merge when ready and Re-request review (issue #14)

- **Re-review rule (`model.awaitingReReview`).** A non-bot reviewer's latest review that requested changes on a commit other than `headOid` is *moved past*: it no longer counts as feedback in `reasons`, so the PR is In review, not Needs fixes. `ask` holds the waiting reviewers not already in `reviews.requested`. A review with no commit oid is never stale. The chip reads "Waiting on @a to re-review", "@a and @b", or "@a and 2 others". Open threads by the same reviewer still make Needs fixes.
- **Q** is Re-request review (`gh pr edit <n> --repo <r> --add-reviewer a,b`). **M** is Merge when ready / Cancel merge on In review cards, behind the ▾.
- **Allow auto-merge** is `repository.autoMergeAllowed` in `merge-detect.graphql`, held in `State.autoMerge` (per session, not in the kv record). GitHub methods and the queue need it true; unknown hides the entry. Comment and label methods skip it. A learned, unconfirmed command (`ask`) is not offered early.
- **Contracts added:** `commands.autoMerge(pr, method)`, `Detected.autoMergeAllowed`, `Model.canMergeWhenReady`, `Model.reviewerList`, `State.setAutoMerge`, `State.reRequested`. `commands.requestReview(pr, logins)` takes a comma-separated list.
- **Pending.** Merge when ready is stored as `pending` (`queue`, `comment` or `label`); a card in In review with `pending` reads "Merges when ready". Auto-merge turned on outside the hub is not shown (the hub fragment keeps `pending` nil).
