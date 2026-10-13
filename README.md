# PR Guide

> [!NOTE]
> PR Guide is in active development. Features, keys and the saved guide format may change between
> versions.

**A Tern plugin for tracking pull requests across repositories, reading their diffs and posting
reviews.**

Once you have a dozen PRs open across several repositories, keeping up with them turns into tab
management. CI is on one page, review comments on another, and the fix you asked an agent for is in
a separate conversation. PR Guide puts all of it in Tern.

## What it does

- **All your PRs on one board.** PRs from every repository are sorted into Needs fixes, In review
  and Ready to merge, and each card says why it's there.
- **Teammates' PRs in one place.** See what's waiting for your review, what's waiting on the author
  and what's approved. A PR you approved comes back to To review only when you're asked again.
- **No trips to the browser.** Read the diff, comment on lines and submit the GitHub review without
  leaving the terminal.
- **Two ways to read a PR.** A file view like GitHub's, or a guided walkthrough written by your
  agent, inspired by Linear Diffs.
- **Fixes done for you.** An agent resolves conflicts and addresses bot reviews in an isolated
  worktree, and you review its commit before anything is pushed. Flaky checks are flagged so you
  can re-run them instead of debugging them.
- **Merging the way each repository does.** PR Guide detects a merge queue, Aviator or a `/merge`
  comment command, and can merge a PR as soon as it's ready.

![The PR hub with pull requests in Needs fixes, In review and Ready to merge](docs/screenshots/hub.png)

## Install

PR Guide needs Tern and the [GitHub CLI](https://cli.github.com) signed in to GitHub.
[OMP](https://omp.sh) is optional. It runs guided reviews and agent fixes, and everything else
works without it.

```sh
gh auth login
tern plugin install github.com/jubbydev/tern-pr-guide
```

Press `⌥⌘R` in Tern, or choose **PR hub** from the command palette. Press `?` on any page for the
keys that apply there. To look around before pointing it at real PRs, run **New PR hub sample
block** for a board of recorded sample data, or **New PR Guide sample block** for a sample PR whose
review is a dry run.

To work on the plugin itself, clone it and run `tern plugin link /path/to/tern-pr-guide`.
**New PR Guide worst-case sample block** opens a PR built to stress the page: long titles and
paths, 60 files, a 12-step change and long comments (`fixtures/pr-worst.json`,
`fixtures/guide-worst.json`). **…, no guide** opens it without the guide, with long model names and
every effort level in the model menu (`fixtures/agent-worst.json`).

## Your pull requests

The **Your pull requests** tab sorts every PR you opened into three columns:

- **Needs fixes:** requested changes, unresolved comments, failing checks, a conflict or a failed
  merge-queue run. Each reason is its own chip on the card.
- **In review:** waiting on a reviewer, on checks or on Tandem.
- **Ready to merge:** approved, passing and free of conflicts.

The **Next up** bar above the board shows the most urgent PR. Drafts and PRs with no activity for
7 days move to a hidden **Inactive** group, where you can select stale PRs and close them together.

A PR leaves the board once it merges, from the hub or anywhere else. The folded **Recently merged**
list at the bottom (`R`) keeps your 20 latest merges from the past 7 days, and ⏎ opens one.

When a PR lands in Needs fixes, its card is outlined in red and the hub's status-line segment
flashes. Failed merges, failing checks and feedback from a person also show a toast. Conflicts
don't, because they arrive in bursts when other PRs merge. The segment stays visible while the hub
is open and shows how many PRs need fixes or review.

**Merging.** Each repository has one merge setting: squash, merge commit, rebase, merge queue, a
comment command such as `/aviator merge`, or a label. PR Guide reads it from the repository's
config, or learns it from how recent PRs were merged and asks you once to confirm. Merge one PR,
select several and merge them together, or set an In review PR to merge as soon as it's ready.

## Review teammates' PRs

The **Review requests** tab sorts the PRs others asked you to review:

- **To review:** requests that name you, including a request to review again after you approved,
  PRs whose review from you was dismissed, and PRs you added by pasting a link.
- **Waiting on author:** you requested changes or left comments.

Below the board, four folded lists keep the rest out of the way. Opening one scrolls it into view and selects its first row, so `j` and `k` carry on from there.

- **Inactive:** requests that name you but have had no activity for 7 days. PRs you added by link
  always stay in To review.
- **Team requests:** PRs that ask a team you're on, such as a CODEOWNERS team, and not you by name.
  They don't count toward the tab's number or Next up. Paste one's link in the add field to move it
  to To review.
- **Approved:** PRs you approved. New commits don't move one back to To review; its card notes
  "New commits since you approved" until the author asks you again. Approved PRs don't count toward
  the tab's number or Next up.
- **Recently opened:** any PR you opened before stays one key away, even after it closes.

## Fix what's blocking

Open a Needs fixes card to go straight to the problems: requested changes, comments, failing checks
and conflicts, each next to its code. Reply to a thread, resolve it, read a check's log or re-run
failed checks from the same page.

- **Check logs.** A failing check with no annotations shows its log, cut to the lines around the
  error, with the changed lines it names shown in their files. This works for GitHub Actions
  (through `gh`) and Buildkite (through the [`bk` CLI](https://github.com/buildkite/cli), signed in
  with `bk auth login`; PR Guide asks for the organization in the check's link). Other CI shows the
  check's summary, and `⇧L` opens its page.

- **Agent fixes.** Your OMP agent resolves a conflict or addresses a bot review in an isolated
  worktree, never in your checkout. You follow its progress on the card.
- **Fewer tokens.** Conflicts are fixed by merging the base branch in. A clean merge costs no
  tokens, lockfiles are regenerated rather than merged, and only the conflicts left over go to the
  agent.
- **Review before push.** The fix opens on a review page that labels every line as from the base
  branch, your branch or the agent. Push unlocks once every conflict is marked reviewed.
- **Sandboxed bot fixes.** When the agent addresses a bot review, it can write only inside its
  worktree.
- **Flaky checks.** A failure that also happens on main, for example "failed 3 of the last 20 runs
  on main", is marked **Likely flaky**, so a re-run is the obvious next step.
- **Feedback summaries.** A one-line summary of what reviewers asked for, such as "Reply to
  @maria-k", followed by one line for each commenter.
- **Tandem.** A PR that Tandem watches goes back to its Tandem coordinator instead of a new agent.

## Read a PR

Open any card to see the whole PR in Tern, with two ways to read it. Press `t` to switch between
them. Comments, reviewed marks and the summary carry over. Under the title, the header shows who opened the PR
and how long ago, as in "jubbydev opened 3h ago".

**Files** works like GitHub's PR page: the description, the changed files as a folder tree,
search across the changed code, and comments on any line. The diff comes from local git, so
GitHub's diff size limit doesn't apply, and large PRs stay responsive. Tests and generated files
come last, under their own folding rows. Code is colored by language, with the changed words of an
edited line marked, for JavaScript and TypeScript, Python, Go, Rust, Ruby, Java, Kotlin, Swift, C
and C++, C#, shell, Lua and Luau, CSS and SCSS, JSON, YAML, TOML and SQL. Other files show plain text.

![The PR file browser with the changed files and description](docs/screenshots/pr-view.png)

**Guided** is an AI walkthrough inspired by Linear Diffs. You see the overall shape of the change
first, then go through it in small steps:

- A plain-language overview and, for some PRs, a before-and-after diagram: one run through the
  code, with what each stage did before the PR above what it does now, the changed parts linked to
  their changes, and a "Check" line naming the consequence to confirm.
- The PR split into a few changes, and each change into steps pinned to their lines.
- Code blocks that start at the enclosing function, method or class, so a step reads in context. When
  that line is far above the change, the block keeps a few lines of context and the hidden lines
  above it are labeled with it.
- Suggested review comments placed next to the code they're about.
- Moved code shown as moved. A block cut from one place and pasted in another, in the same file or
  a different one, is drawn in neutral gray instead of red and green, with a label such as "Moved
  from src/a.ts:12" or "Moved to line 40".
- Supporting changes folded away. Files no step visits sit under "Supporting changes", followed by
  a folded "Tests" group and a folded "Generated" group (files marked `linguist-generated` in
  `.gitattributes`). A test file a step visits stays in its step. The guide agent never reads
  generated files, so no step or comment points at one, and lockfiles are left out of the PR
  altogether.
- Guides saved in the repository, so a reopened PR loads its guide right away in every worktree of
  the clone.

Generating a guided review starts two OMP runs at once. The explanation writes the overview and
steps, and the page turns guided as soon as it lands, with "Reviewing for issues…" in the status line
while the review is still drafting comments. The comments and summary join the page when the review
finishes. A summary you already edited is kept.

![A guided review with an overview, diagram and the first change](docs/screenshots/overview.png)

![A guided step with its code and a suggested review comment](docs/screenshots/step.png)

## Choose models and a review lens

Guided reviews need OMP. Before generating one, click the model button (or press `⇧M`). The menu
has two slots, **Explanation** and **Review**, and `Tab` switches between them:

- **Explanation:** the model and effort that write the walkthrough. A fast model at low effort is
  enough.
- **Review:** the model and effort that draft comments on problems and questions. A strong model
  works best, and higher effort finds more. Choose **Off** to get the explanation only, with no
  drafted comments.

Until you choose an explanation model it uses the review model. The model button shows the
explanation model, then the review model, each with its effort, then the lens. The PR hub's Settings
(`⇧S`) show the same menu and save the same choice. Agent fixes and feedback summaries use the review
model.

The lens control is on the Review slot, because a lens steers only the review comments. PR Guide
ships four lenses:

- **Balanced:** the comments worth making on the whole PR.
- **Security:** the change from an attacker's point of view.
- **Architecture:** boundaries, dependencies and long-term cost.
- **Quick skim:** only the comments that matter.

![Choosing an OMP model, effort and review lens](docs/screenshots/lenses.png)

You can also write your own. Choose **Edit lenses…** to open your lenses folder, and add a Markdown
file for each lens:

```markdown
# Performance

Slow paths and wasted work.

Check for repeated work in loops, unnecessary copying, blocking calls on hot paths and queries that
could be batched. Comment only when the cost will matter in practice.
```

A custom lens with the same name as a built-in one replaces it. Every lens writes the same comment
format, so any review opens the same way.

## Post the review

The agent's comments are suggestions until you add them to your review. Open the review panel, pick
Comment, Approve or Request changes, edit the summary, and submit everything as one GitHub review.

![The review panel with comments, summary and verdict](docs/screenshots/review.png)

- **Two presses to submit.** The first press shows what will be posted and where. Any other key
  cancels.
- **No stale reviews.** If the PR has new commits since you started reading, submission stops until
  you refresh.
- **Dry runs.** The sample block and any guide opened with `post=false` save the review to a JSON
  file under `/tmp` and never write to GitHub.

## Keyboard reference

Press `?` on any PR Guide page for the keys that apply there.

### PR hub

| Key | Action |
|---|---|
| `⌥⌘R` | Open or focus the hub |
| `⌥⇧⌘R` | Open the hub so `⏎` starts a guided review |
| `h` `j` `k` `l` or arrows | Move between cards |
| `.` | Select the most urgent PR |
| `⏎` or click | Open the PR, its fixes page or a ready agent fix |
| `⇧⏎` | Open and start a guided review |
| `T` | Switch between your PRs and review requests |
| `/` | Search |
| `F` | Filter by repository |
| `S` | Sort |
| `I` | Show or hide inactive PRs, on either tab |
| `⇧T` | Show or hide team review requests |
| `A` | Show or hide approved PRs, on Review requests |
| `R` | Show or hide recently merged PRs, or recently opened PRs on Review requests |
| `N` | Add a PR by link |
| `⇧S` | Settings: the explanation and review models, their effort and the lens, in the same menu as the review page, and whether GitHub links open in Tern or the default browser (`L` switches while the search field is empty). `⇧M` opens it too |
| `A` | Run the selected card's main action, on your PRs |
| `⇧A` | Summarize feedback or return a retained worktree |
| `C` | Copy the PR title and link |
| `M` | Merge, merge when ready or cancel a pending merge |
| `,` | Choose the repository's merge method |
| `U` | Update the branch |
| `⇧R` | Re-run failed checks |
| `Q` | Re-request review |
| `O` | Choose a clone or open a retained worktree |
| `Space` or ⌘-click | Select cards for a batch action |
| `⇧X` | Select stale PRs |
| `X` | Remove an added review request or close selected stale PRs |
| `⌘R` | Refresh |
| `⌘⏎` | Confirm an inline question |
| `Esc` | Cancel, close or clear the selection |

### PR view

| Key | Action |
|---|---|
| `j` `k` | Next or previous step |
| `n` `p` | Next or previous suggested comment |
| `⏎` | Mark the step reviewed and move on |
| `⇧⏎` | Mark the whole change reviewed |
| `v` | Mark the whole file reviewed |
| `t` | Switch between Guided and Files |
| `b` | Hide or show the file tree in the file view |
| `/` | Search steps, files, comments and code |
| `s` | Show supporting changes |
| `o` | Open all supporting files and unfold Tests; generated files stay as they are |
| `c` | Comment on the current step |
| `a` `d` | Keep or dismiss a suggested comment |
| `i` | Show the PR description |
| `m` | Mark or unmark everything reviewed |
| `g` | Open the PR on GitHub |
| `⇧G` | Generate a guided review |
| `⇧M` | Choose the explanation and review models, their effort, and the lens |
| `Tab` | In that menu, switch between Explanation and Review |
| `⌃E` | Edit lenses |
| `r` | Open the review panel |
| `x` | Include or leave out the selected review comment |
| `a` | Include or exclude every review comment |
| `e` | Edit the review summary |
| `1` `2` `3` | Comment, Approve or Request changes |
| `⌘⏎` | Submit the review |
| `Esc` | Close the review panel |

### Fixes page

Replies and resolves write to GitHub right away.

| Key | Action |
|---|---|
| `j` `k` | Move through requested changes, comments, failing checks and conflicts |
| `R` | Reply to the thread |
| `⌘⏎` | Post the reply |
| `E` | Resolve the thread |
| `⇧L` | Open the check's log |
| `⇧R` | Re-run failed checks |
| `G` | Open GitHub's conflict editor |
| `B` | Show bot comments |
| `Esc` | Back to the hub with the same card selected |

### Agent fix review

| Key | Action |
|---|---|
| `j` `k` | Move between conflicts |
| `⏎` | Mark the conflict reviewed |
| `B` | Show the original conflict |
| `P` | Push, once every conflict is reviewed |
| `D` | Discard the fix, after a confirmation |
| `Esc` | Back to the hub |

## For tool authors

Open a PR from another tool with the `prguide.guide` block:

```lua
cx:new_block("prguide.guide", {"pr=123", "repo=/path/to/your/clone"}, "tab")
```

| Argument | Meaning |
|---|---|
| `repo=` | A path inside the repository clone |
| `pr=` | A PR number or URL |
| `guide=` | A saved guide JSON file; see [GUIDE.md](GUIDE.md) |
| `post=false` | Save the review under `/tmp` |
| `generate=true` | Start a guided review when the PR opens |

PR Guide fetches the PR into `refs/prguide/<number>/*` and doesn't touch your branches or working
tree. When there's no local clone to use, it keeps a light copy under Tern's plugin-data folder and
reuses it for later PRs. Saved guides are stored at `.git/prguide/<number>.json`, in the format
documented in [GUIDE.md](GUIDE.md).

The hub uses about 130 GitHub GraphQL points an hour while it's open, against GitHub's limit of
5,000. It loads from its cache, checks for changes with a conditional request, and batches its
queries. Opening a PR fetches its metadata once, and the diff comes from local git.
