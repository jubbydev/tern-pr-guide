--!strict
-- The review page block: opens the PR its arguments name (or the bundled sample), draws the page, and turns clicks and keys into state changes plus the
-- scrolling, focusing and animation timing only a live window can do.
local Agent = require("./agent")
local AgentHost = require("./agent-host")
local Diff = require("./diff")
local Fetch = require("./fetch")
local Fields = require("./text-field")
local Guide = require("./guide")
local Host = require("./host")
local Keys = require("./keys")
local Links = require("./links")
local ModelBox = require("./model-box")
local Notice = require("./view/notice")
local Page = require("./view/page")
local Pr = require("./pr")
local Prdata = require("./prdata")
local Review = require("./review")
local State = require("./state")

type State = State.State
type Handler = (s: State, cx: BlockCx, value: string) -> ()

-- How the block was opened: a PR and its checkout, a directory with no PR (the PR hub picks one), or
-- neither for the bundled sample.
type Options = { pr: string?, repo: string?, guide: string?, post: boolean, generate: boolean?, worst: boolean? }

-- The review page once its PR has loaded; before that, what loading is doing.
type Block = {
 opts: Options,
 -- The directory the block was opened in; a PR link may name a checkout beside or below it.
 dir: string,
 -- The PR as the reader named it ("#350"), for the title and the loading page.
 name: string,
 repo: Fetch.Repo?,
 notice: Notice.Notice,
 page: State?,
 -- The page shows a guide file rather than the default walkthrough.
 guided: boolean,
 -- The view the reader last chose on a page with a guide, kept for the block's other PRs.
 view: State.ViewId?,
 -- The reader's AI agent, once found, and its run writing a guide.
 ai: Agent.Run?,
 -- Why the agent isn't available, once looked for and missing.
 noAgent: string?,
 -- `generate=true` has been settled: a run started, or a reason not to.
 autoDone: boolean?,
}

local ARGS = "pr=<number or URL> with repo=<checkout path or a directory to look in>, optionally guide=<file>, post=false for a dry run and generate=true to start an AI guided review once the PR opens"
local SAMPLE_GUIDE = "fixtures/guide-350.json"

-- The closing animations in guide.css last 150-200 ms.
local CLOSE_MS = 190

-- Sends frame ops after the render that draws their targets. A target the render dropped makes
-- the frame fail, which leaves nothing to do.
local function frameLater(cx: BlockCx, ops: { any })
 Host.timer(1, function()
  pcall(function() cx:frame(ops) end)
 end)
end

-- Opens a GitHub link where the PR hub's Settings say: Tern's browser, or the system's default browser.
local function openLink(cx: BlockCx, url: string)
 if Fetch.linkTarget() == "tern" then return cx:open(url) end
 Fetch.openInBrowser(url, function(err)
  if err then pcall(function() cx:toast("error", "Couldn't open the link: " .. err, url) end) end
 end)
end

-- Moves straight to `path`, so a clicked jump reads as intended flashing the ring of block `ring`
-- or pulsing the lines of the step `step`. Tern's reveal cannot animate and a glide faked from
-- line scrolls stuttered.
local function jump(s: State, cx: BlockCx, path: string, align: string, ring: string?, step: string?)
 s.flash, s.flashStep, s.flashCount = ring, step, s.flashCount + 1
 frameLater(cx, { { "reveal", path, align } })
end

-- Explicit jumps (clicking a step, file, or diagram box) land the step's block, or for a shared
-- block the step's first lines, at the top and flash: the step's lines pulse in a guided block,
-- the block's ring flashes otherwise. j/k only scroll when the next step is off screen, only as far
-- as needed, and never flash.
local function follow(s: State, cx: BlockCx, explicit: boolean)
 local step = State.currentStep(s)
 local open = State.plan(s).open[step.block] == true
 local path = Page.blockPath(step.block)
 local span = s.spans[step]
 if open and span and #Review.stepsOfBlock(s.review, step.block) > 1 then path = Page.stepPath(step, span.first) end
 local pulse = explicit and open and span ~= nil
 jump(s, cx, path, if explicit then "start" else "nearest", if explicit and not pulse then step.block else nil, if pulse then step.key else nil)
end

-- Plays the closing animation of `ids`, then applies the change that removes them. A key press
-- applies it at once: keys are pressed too often to wait on motion.
local function closeAfter(s: State, cx: BlockCx, ids: { string }, apply: () -> ())
 if s.keyed then return apply() end
 for _, id in ids do s.closing[id] = true end
 cx:render()
 Host.timer(CLOSE_MS, function()
  for _, id in ids do s.closing[id] = nil end
  apply()
  cx:render()
 end)
end

-- Marks the steps `keys` reviewed, folding the code of each block that has all its steps reviewed
-- and moving past the last one, or, when all already are, unmarks them. Instant: marking is the
-- most pressed key of a review. Moving on within a shared block scrolls to the next step.
local function markSteps(s: State, cx: BlockCx, keys: { string })
 local r = s.review
 if Review.allReviewed(r, keys) then
  Review.unmark(r, keys)
  for _, id in Review.blocksOfKeys(r, keys) do s.peek[id] = nil end
  return
 end
 local last = Review.lastStep(r, keys)
 local from = r.steps[r.cur]
 for _, id in Review.blocksOfKeys(r, Review.mark(r, keys)) do
  if Review.blockReviewed(r, id) then State.setOpen(s, id, false) end
 end
 if last > 0 then Review.advance(r, last) end
 local now = r.steps[r.cur]
 if now ~= from and now.block == from.block and #Review.stepsOfBlock(r, now.block) > 1 then follow(s, cx, false) end
end

local function markFile(s: State, cx: BlockCx, path: string)
 local r = s.review
 local keys = Review.keysOfFile(r, path)
 if #keys > 0 then
  markSteps(s, cx, keys)
 elseif r.filesViewed[path] then
  r.filesViewed[path] = nil
 else
  if s.fileOpen[path] then State.setOpen(s, State.supportingBlock(path), false) end
  r.filesViewed[path] = true
 end
end

-- Marks every supporting file reviewed, folding the open ones, or unmarks them all when all are.
local function markSupporting(s: State)
 local r = s.review
 local files = Review.supportingFiles(r)
 local all = true
 for _, file in files do
  if not r.filesViewed[file.path] then all = false end
 end
 for _, file in files do
  r.filesViewed[file.path] = if all then nil else true
  if not all then State.setOpen(s, State.supportingBlock(file.path), false) end
 end
end

-- Marks every changed file reviewed, folding its code, or unmarks them all when all already are.
local function markAll(s: State)
 local r = s.review
 local all = Review.counts(r).filesReviewed == #r.pr.files
 local keys = {}
 for _, step in r.steps do table.insert(keys, step.key) end
 if all then
  Review.unmark(r, keys)
  for _, id in Review.blocksOfKeys(r, keys) do s.peek[id] = nil end
 else
  for _, id in Review.blocksOfKeys(r, Review.mark(r, keys)) do State.setOpen(s, id, false) end
 end
 for _, file in Review.supportingFiles(r) do
  r.filesViewed[file.path] = if all then nil else true
  if not all then State.setOpen(s, State.supportingBlock(file.path), false) end
 end
end

local function toggleHelp(s: State, cx: BlockCx)
 if s.helpOpen then closeAfter(s, cx, { "help" }, function() s.helpOpen = false end) else s.helpOpen = true end
end

local function closeReview(s: State, cx: BlockCx)
 closeAfter(s, cx, { "review" }, function() s.reviewOpen = false end)
end

local function gotoSuggestion(s: State, cx: BlockCx, id: string)
 local r = s.review
 local comment = Review.suggestion(r, id)
 local i = if comment then Review.stepShowing(r, comment.file, comment.line) else nil
 if not i then return end
 State.visitStep(s, i)
 r.focus = id
 jump(s, cx, Page.suggestionPath(r.steps[i].block, id), "start", nil, nil)
end

local function gotoOwn(s: State, cx: BlockCx, n: number)
 local r = s.review
 local own = r.own[n]
 local i = if own then State.stepFor(s, own.file, own.to) else nil
 if not i then return end
 r.cur = i
 follow(s, cx, true)
end

local function stepSuggestion(s: State, cx: BlockCx, delta: number)
 local r = s.review
 local order = Review.suggestionOrder(r)
 if #order == 0 then return end
 local at = (if r.focus then table.find(order, r.focus) else nil) or (if delta > 0 then 0 else #order + 1)
 gotoSuggestion(s, cx, order[math.clamp(at + delta, 1, #order)])
end

-- Runs a model menu action on the page's agent, saving what it changed.
local function modelAction(s: State, act: string, value: string)
 local agent = (s.ai :: Agent.Run).agent
 local outcome = ModelBox.act(s.models :: ModelBox.ModelBox, agent, act, value) :: ModelBox.Outcome
 if outcome.save then AgentHost.saveChoice(agent) end
 s.models = if outcome.close then nil else outcome.box
end

-- Takes you to a search result: a step, a comment, a file's first block, or one changed line,
-- opening whatever hides it and marking the line.
local function searchGo(s: State, cx: BlockCx, n: number)
 local result = (s.search :: State.SearchBox).results[n]
 if not result then return end
 s.search = nil
 local go = result.go
 if go.step then
  s.review.cur = go.step
  follow(s, cx, true)
 elseif go.suggestion then
  gotoSuggestion(s, cx, go.suggestion)
 elseif go.own then
  gotoOwn(s, cx, go.own)
 elseif go.file then
  local blockId, isStep = State.showFile(s, go.file, go.entry)
  local path = if go.entry then Page.linePath(blockId, go.entry) else Page.blockPath(blockId)
  jump(s, cx, path, "start", if isStep then blockId else nil, nil)
 end
end

local function openComposer(s: State, cx: BlockCx, file: string, from: number, to: number)
 local blockId = State.openComposer(s, file, from, to)
 cx:render()
 frameLater(cx, { { "reveal", Page.composerPath(blockId), "nearest" }, { "focus", Page.composerFieldPath(blockId) } })
end

local function commentClick(s: State, cx: BlockCx, file: string, line: number)
 local from, to, extends = State.commentRange(s, file, line)
 if not extends then s.composer = nil end
 if from and to then openComposer(s, cx, file, from, to) end
end

local function editSummary(s: State, cx: BlockCx)
 s.editingSummary = true
 frameLater(cx, { { "focus", Page.summaryFieldPath } })
end

local function toggleStepBlock(s: State, cx: BlockCx, key: string)
 if State.plan(s).open[key] then
  closeAfter(s, cx, { "peek:" .. key }, function() State.setOpen(s, key, false) end)
 else
  State.setOpen(s, key, true)
 end
end

local function gotoStep(s: State, cx: BlockCx, i: number, explicit: boolean)
 s.review.cur, s.review.focus = math.clamp(i, 1, #s.review.steps), nil
 follow(s, cx, explicit)
end

-- Shows the guided walkthrough or the file view, each as the reader left it, from its top. A
-- switch swaps the whole page, so it shows at once, mouse or key.
local function switchView(s: State, cx: BlockCx, to: State.ViewId)
 if not State.switchView(s, to) then return end
 s.keyed = true
 frameLater(cx, { { "scroll", "main", "start" } })
end

-- Sends the review once: the page shows it sending, then where it went or why it didn't. A review
-- bound for GitHub first asks to be confirmed, and the next submit posts it; any other action
-- cancels the ask (see dispatch).
local function submit(s: State, cx: BlockCx)
 local r, out = s.review, s.submit
 s.editingSummary = false
 if r.posted or out.sending then return end
 if not out.dryRunPath and not out.confirming then
  out.confirming = true
  return
 end
 local verdict, payload = r.verdict, Review.reviewPayload(r)
 out.confirming, out.sending, out.error = false, true, nil
 Prdata.submitReview(r.pr, payload, out, function(delivery, err)
  out.sending, out.error = false, err
  if delivery then r.posted = { verdict = verdict, payload = payload, delivery = delivery } end
  cx:render()
 end)
end

local ACTIONS: { [string]: Handler } = {
 -- reading
 ["step"] = function(s, cx, delta) gotoStep(s, cx, s.review.cur + (tonumber(delta) :: number), false) end,
 ["goto-step"] = function(s, cx, n) gotoStep(s, cx, tonumber(n) :: number, true) end,
 ["next-suggestion"] = function(s, cx, delta) stepSuggestion(s, cx, tonumber(delta) :: number) end,
 ["peek"] = toggleStepBlock,
 ["reveal"] = function(s, _, value)
  local blockId, first, last = string.match(value, "^(.*)|(%d+)|(%d+)$")
  State.reveal(s, blockId :: string, tonumber(first) :: number, tonumber(last) :: number)
 end,
 ["whole"] = function(s, _, blockId) State.toggleWhole(s, blockId) end,
 ["toggle-flow"] = function(s, cx)
  if s.flowOpen then closeAfter(s, cx, { "flow" }, function() s.flowOpen = false end) else s.flowOpen = true end
 end,
 ["toggle-description"] = function(s, cx)
  if s.descriptionOpen then closeAfter(s, cx, { "description" }, function() s.descriptionOpen = false end) else s.descriptionOpen = true end
 end,
 ["toggle-folder"] = function(s, _, path) s.foldedFolders[path] = if s.foldedFolders[path] then nil else true end,
 ["toggle-group"] = function(s, cx)
  if s.supportingOpen then closeAfter(s, cx, { "group" }, function() s.supportingOpen = false end) else s.supportingOpen = true end
 end,
 ["toggle-file"] = function(s, cx, path)
  local blockId = State.supportingBlock(path)
  if State.plan(s).open[blockId] then
   closeAfter(s, cx, { "file:" .. path }, function() State.setOpen(s, blockId, false) end)
  else
   State.setOpen(s, blockId, true)
  end
 end,
 ["open-all-supporting"] = function(s) State.toggleAllSupporting(s) end,
 ["toggle-help"] = toggleHelp,
 ["toggle-tree"] = function(s) s.treeHidden = not s.treeHidden end,
 ["dismiss"] = function(s, cx)
  s.review.focus = nil
  if s.helpOpen then toggleHelp(s, cx) end
 end,
 ["scroll"] = function(_, cx, how) cx:frame({ { "scroll", "main", how } }) end,
 ["open-github"] = function(s, cx) openLink(cx, s.review.pr.url) end,
 ["view"] = function(s, cx, to) switchView(s, cx, to :: State.ViewId) end,
 ["toggle-view"] = function(s, cx) switchView(s, cx, if s.view == "guided" then "files" else "guided") end,

 -- marking
 ["review-step"] = function(s, cx, key) markSteps(s, cx, { key }) end,
 ["mark-block"] = function(s, cx, id)
  local keys = {}
  for _, step in Review.stepsOfBlock(s.review, id) do table.insert(keys, step.key) end
  markSteps(s, cx, keys)
 end,
 ["mark-change"] = function(s, cx, n) markSteps(s, cx, Review.keysOfChange(s.review, tonumber(n) :: number)) end,
 ["mark-file"] = markFile,
 ["mark-supporting"] = markSupporting,
 ["mark-all"] = markAll,

 -- suggestions and comments
 ["decide"] = function(s, _, value)
  local id, decision = string.match(value, "^(.-)|(.*)$")
  Review.decide(s.review, id :: string, if decision == "undo" then nil else decision :: Review.Decision)
 end,
 ["decide-current"] = function(s, _, decision)
  local comment = Review.currentSuggestion(s.review)
  if comment then Review.decide(s.review, comment.id, decision :: Review.Decision) end
 end,
 ["goto-suggestion"] = function(s, cx, id)
  s.reviewOpen = false
  gotoSuggestion(s, cx, id)
 end,
 ["goto-own"] = function(s, cx, n)
  s.reviewOpen = false
  gotoOwn(s, cx, tonumber(n) :: number)
 end,
 ["comment"] = function(s, cx, value)
  local file, line = string.match(value, "^(.*)|(%d+)$")
  commentClick(s, cx, file :: string, tonumber(line) :: number)
 end,
 ["comment-step"] = function(s, cx)
  local step = State.currentStep(s)
  local from, to = Diff.commentableRange(s.diffs[step.file], step.at.from, step.at.to)
  if from and to then openComposer(s, cx, step.file, from, to) end
 end,
 ["comment-save"] = function(s) State.saveComposer(s) end,
 ["comment-cancel"] = function(s) s.composer = nil end,

 -- search
 ["open-search"] = function(s, cx)
  State.openSearch(s)
  frameLater(cx, { { "focus", Page.searchFieldPath } })
 end,
 ["search-run"] = function(s) State.runSearch(s, s.search :: State.SearchBox) end,
 ["search-move"] = function(s, _, delta) State.moveSearch(s.search :: State.SearchBox, tonumber(delta) :: number) end,
 ["search-pick"] = function(s, cx) searchGo(s, cx, (s.search :: State.SearchBox).selected) end,
 ["search-go"] = function(s, cx, n) searchGo(s, cx, tonumber(n) :: number) end,
 ["search-close"] = function(s) s.search = nil end,

 -- the model dropdown
 ["toggle-models"] = function(s, cx)
  local run = s.ai
  if s.models then
   s.models = nil
   return
  end
  if not run or Agent.busy(run) then return end
  AgentHost.refreshChoice(run.agent)
  Fetch.refreshLenses(run.agent)
  s.models = ModelBox.open(run.agent, "explain")
  frameLater(cx, { { "focus", Page.modelFieldPath } })
 end,
 ["models-slot"] = function(s, _, slot) modelAction(s, "models-slot", slot) end,
 ["models-filter"] = function(s) modelAction(s, "models-filter", "") end,
 ["models-move"] = function(s, _, delta) modelAction(s, "models-move", delta) end,
 ["models-top"] = function(s) modelAction(s, "models-top", "") end,
 ["models-effort"] = function(s, _, delta) modelAction(s, "models-effort", delta) end,
 ["models-pick"] = function(s) modelAction(s, "models-pick", "") end,
 ["model-row"] = function(s, _, n) modelAction(s, "model-row", n) end,
 ["model-effort"] = function(s, _, effort) modelAction(s, "model-effort", effort) end,
 ["models-lens"] = function(s, _, delta) modelAction(s, "models-lens", delta) end,
 ["model-lens"] = function(s, _, n) modelAction(s, "model-lens", n) end,
 ["edit-lenses"] = function(s, cx)
  local folder, err = Fetch.prepareLensFolder()
  s.models = nil
  if folder then cx:open(folder) else cx:toast("error", "Couldn't open your lenses folder", err) end
 end,

 -- the review
 ["open-review"] = function(s) State.openReview(s) end,
 ["toggle-review"] = function(s, cx)
  s.editingSummary = false
  if s.reviewOpen then closeReview(s, cx) else State.openReview(s) end
 end,
 ["review-move"] = function(s, cx, delta)
  local item = State.moveReviewCursor(s, tonumber(delta) :: number)
  if item then frameLater(cx, { { "reveal", Page.reviewRowPath(item), "nearest" } }) end
 end,
 ["toggle-item"] = function(s, _, n) State.toggleItem(s, tonumber(n) :: number) end,
 ["toggle-all"] = function(s) Review.toggleAll(s.review) end,
 ["verdict"] = function(s, _, id) Review.setVerdict(s.review, id) end,
 ["edit-summary"] = editSummary,
 ["done-summary"] = function(s) s.editingSummary = false end,
 ["submit-review"] = submit,
 ["open-posted"] = function(s, cx)
  local posted = s.review.posted
  if posted and posted.delivery.kind == "posted" then openLink(cx, posted.delivery.url) end
 end,
}

local function dispatch(s: State, cx: BlockCx, action: Keys.Action)
 if action.act ~= "submit-review" then s.submit.confirming = false end
 local handler = ACTIONS[action.act]
 if handler then handler(s, cx, action.value or "") end
end

-- Reads `name=value` block arguments; none at all opens the bundled sample.
local function options(args: { string }): (Options?, string?)
 local given: { [string]: string } = {}
 for _, arg in args do
  local name, value = string.match(arg, "^(%a+)=(.*)$")
  -- sample=worst opens the worst-case sample (fixtures/*-worst.json) with its guide, and
  -- sample=worst-plain without one, offering the agent: they stress-test the page's layout.
  if name == "sample" and value == "worst" and #args == 1 then return { guide = "fixtures/guide-worst.json", post = false, worst = true }, nil end
  if name == "sample" and value == "worst-plain" and #args == 1 then return { post = false, worst = true }, nil end
  if name ~= "pr" and name ~= "repo" and name ~= "guide" and name ~= "post" and name ~= "generate" then
   return nil, "Unknown argument \"" .. arg .. "\". The block takes " .. ARGS .. "."
  end
  if (name == "post" or name == "generate") and value ~= "true" and value ~= "false" then
   return nil, name .. "= takes true or false, not \"" .. value .. "\". The block takes " .. ARGS .. "."
  end
  given[name :: string] = value :: string
 end
 local pr, repo = given.pr, given.repo
 if not pr and not repo then
  if given.generate == "true" then return nil, "generate=true needs repo=. The block takes " .. ARGS .. "." end
  return { guide = given.guide or SAMPLE_GUIDE, post = false }, nil
 end
 if pr and (repo or "") == "" then return nil, "pr= needs repo=. The block takes " .. ARGS .. "." end
 return { pr = pr, repo = repo, guide = given.guide, post = given.post ~= "false", generate = given.generate == "true" }, nil
end

local function nameOf(pr: string?): string
 if not pr then return "" end
 local number = string.match(pr, "^#?(%d+)$") or string.match(pr, "/pull/(%d+)")
 return if number then "#" .. number else pr
end

-- Offers the reader's agent while the page shows the default walkthrough, and shows its review
-- still going over a guide that arrived first.
local function offerAgent(b: Block)
 if b.page then b.page.ai = if not b.guided or (b.ai and b.ai.reviewing) then b.ai else nil end
end

-- Keeps the view the reader is in, so the block's next PR with a guide opens in it.
local function remember(b: Block, s: State)
 if State.switchable(s) then b.view = s.view end
end

-- Shows `pr` with `guide`, from a guide file when `guided`. Submitting posts to GitHub once the
-- reader confirms, unless the block was opened with `post=false` or has no checkout (the sample):
-- then it is a dry run.
local function showGuide(b: Block, pr: Pr.PR, guide: Guide.Guide, guided: boolean)
 local repo = if b.repo then b.repo.root else nil
 local dryRunPath = if b.opts.post and repo then nil else Prdata.dryRunPath(pr.number)
 b.page, b.guided = State.new(pr, guide, { repo = repo, dryRunPath = dryRunPath }), guided
 if b.view == "files" and b.page and State.switchable(b.page) then State.switchView(b.page, "files") end
 offerAgent(b)
end

-- The checkout's review file for `pr`, when there is one: nil and why when it can't be used.
local function reviewFile(b: Block, pr: Pr.PR): (Guide.Draft?, string?)
 local repo = b.repo
 if b.opts.guide or not repo then return nil, nil end
 local path = Fetch.reviewPath(repo, pr.number)
 if not Host.fs.exists(path) then return nil, nil end
 local draft, problem = Guide.readDraft(path, pr)
 if draft then return draft, nil end
 return nil, "Couldn't use the review comments in " .. path .. ": " .. (problem :: string)
end

-- Shows `pr` with the guide the options name, else the checkout's guide for it, else the default
-- walkthrough, with the checkout's review file on top. Returns why a review file was left out.
local function showPr(b: Block, pr: Pr.PR): string?
 if #pr.files == 0 then
  b.notice = Notice.failed(b.name, "This PR has no file changes to show (lockfiles are left out).")
  return nil
 end
 local path = b.opts.guide
 if not path and b.repo and Host.fs.exists(Fetch.guidePath(b.repo, pr.number)) then path = Fetch.guidePath(b.repo, pr.number) end
 local guide, problem = Guide.defaultGuide(pr), nil
 if path then guide, problem = Guide.read(path, pr) end
 if not guide then
  b.notice = Notice.failed(b.name, "Couldn't use the guide " .. (path :: string) .. ": " .. (problem :: string))
  return nil
 end
 local draft, unusable = reviewFile(b, pr)
 showGuide(b, pr, if draft then Guide.withDraft(guide, draft) else guide, path ~= nil)
 return unusable
end

-- Has the reader's agent explain the page's PR and, side by side, draft review comments, counting
-- the seconds they take. The explanation replaces the default walkthrough, keeping what the reader
-- wrote; the review lands on whichever page is shown once the explanation has settled, or waits in
-- its file for the explanation to pick it up. One run at a time, and only while the page has no
-- guide, as the button is.
local function generate(b: Block, cx: BlockCx)
 local run, s, repo = b.ai, b.page, b.repo
 if not run or Agent.busy(run) or not s or not repo or b.guided then return end
 local pr = s.review.pr
 local started = Host.now()
 local ticker: TimerHandle
 local function tick()
  run.seconds = math.floor((Host.now() - started) / 1000)
  cx:render()
  if Agent.busy(run) then ticker = Host.timer(1000, tick) end
 end
 local function settled()
  if not Agent.busy(run) then ticker:cancel() end
  offerAgent(b)
  cx:render()
 end
 Agent.start(run, { explain = Fetch.expectedSeconds("explain"), review = Fetch.expectedSeconds("review") })
 ticker = Host.timer(1000, tick)
 -- With the review off, a review file left by an earlier run isn't this run's.
 local reviewed = run.reviewing
 AgentHost.explain(run.agent, repo, pr, function(guide, err)
  run.explaining, run.error = false, err
  local landed = if reviewed and not run.reviewing then reviewFile(b, pr) else nil
  if guide then
   Fetch.saveSeconds("explain", run.seconds)
   local before = b.page :: State
   b.view = nil
   showGuide(b, pr, if landed then Guide.withDraft(guide, landed) else guide, true)
   local page = b.page :: State
   State.carryOver(before, page)
   page.arrival = "guide"
   cx:toast("success", "AI guided review ready")
  elseif landed and b.page then
   State.mergeDraft(b.page, landed)
  end
  settled()
 end)
 if run.reviewing then
  AgentHost.draftReview(run.agent, repo, pr, function(draft, err)
   run.reviewing = false
   if draft then
    Fetch.saveSeconds("review", run.seconds)
    if not run.explaining and b.page then
     State.mergeDraft(b.page, draft)
     cx:toast("success", if #draft.comments == 1 then "1 review comment drafted" else #draft.comments .. " review comments drafted")
    end
   else
    cx:toast("error", "Couldn't draft review comments: " .. (err :: string))
   end
   settled()
  end)
 end
end

-- With `generate=true`, starts the run as soon as the PR's page and the agent are both ready: the
-- page shows the run going. A PR with a guide opens as it is, and with no agent the page opens
-- as usual and a toast says why. Decided once.
local function autoGenerate(b: Block, cx: BlockCx)
 if not b.opts.generate or b.autoDone or not b.page then return end
 if b.guided then
  b.autoDone = true
 elseif b.ai then
  b.autoDone = true
  generate(b, cx)
 elseif b.noAgent then
  b.autoDone = true
  cx:toast("info", "No AI guided review was started", "The page opened without one: " .. b.noAgent .. ".")
 end
end

-- Loads `pr` from the block's checkout, showing each stage, then shows it.
local function loadPr(b: Block, cx: BlockCx, pr: string)
 local repo = b.repo :: Fetch.Repo
 Prdata.openPr({ pr = pr, repo = repo.root, cache = repo.cache }, function(stage)
  b.notice = Notice.loading(b.name, stage, b.notice)
  cx:render()
 end, function(loaded, err)
  if loaded then
   Fetch.rememberPr(loaded)
   local unusable = showPr(b, loaded)
   if unusable then cx:toast("error", unusable) end
  else
   b.notice = Notice.failed(b.name, err :: string)
  end
  autoGenerate(b, cx)
  cx:render()
 end)
end

-- Opens `pr`, a number or a GitHub PR link. A link to another repo's PR first moves the block to a
-- checkout of that repo, since numbers and commits only mean something there: one next to this
-- block's, else PR Guide's own saved copy, which the first open of that repo downloads.
local function openPr(b: Block, cx: BlockCx, pr: string)
 b.name = nameOf(pr)
 b.notice = Notice.loading(b.name, "", nil)
 local slug = Links.linkRepo(pr)
 if not slug then
  if b.repo then return loadPr(b, cx, pr) end
  b.notice = Notice.failed(b.name, "A PR number needs a checkout to read it from. Paste the PR's link instead.")
  return
 end
 b.notice = Notice.loading(b.name, "Finding a checkout of " .. slug, nil)
 Fetch.checkoutFor(b.repo, b.dir, slug, function(found)
  if found then
   b.repo = found
   loadPr(b, cx, pr)
  else
   local saved, why = Fetch.savedCopy(Links.linkHost(pr), slug)
   if saved then
    b.repo = saved
    loadPr(b, cx, pr)
   else
    b.notice = Notice.failed(b.name, why :: string)
   end
  end
  cx:render()
 end)
end

-- The action a click or a pick in the view stands for: a control's own action, or the view tabs'
-- choice, which is the `view=<id>` the old segments sent.
local function actionOf(b: Block, ev: UiEvent): Keys.Action?
 if ev.ev == "action" then return { act = ev.act, value = ev.value } end
 if ev.ev == "select" and b.page and ev.id == Page.viewTabsPath and ev.item then return { act = "view", value = ev.item } end
 return nil
end

local block: BlockDef<Block> = {
 init = function(cx: BlockCx, args: { string }): Block
  local opts, problem = options(args)
  if not opts then return { opts = { post = false }, dir = "", name = "", notice = Notice.failed("", problem :: string), guided = false } end
  local pr, dir = opts.pr, opts.repo
  local b: Block = { opts = opts, dir = dir or "", name = nameOf(pr), notice = if pr then Notice.loading(nameOf(pr), "") else Notice.findingRepo(), guided = false }
  if opts.worst then
   showPr(b, Pr.sample("worst"))
   if not opts.guide then b.ai = Agent.idle(Host.json.decode(Host.fs.read("fixtures/agent-worst.json"))) end
   offerAgent(b)
   return b
  end
  if not dir then
   showPr(b, Pr.sample("350"))
   return b
  end
  if not pr then
   -- The PR hub is the way to a PR.
   b.notice = Notice.message("Review a pull request", "Open a pull request from the PR hub (⌥⌘R)")
   return b
  end
  -- Starts after init returns, so each stage renders over a block that exists.
  Host.timer(0, function()
   AgentHost.findAgent(function(agent, why)
    if not agent then
     b.noAgent = why or "the AI agent isn't available"
     autoGenerate(b, cx)
     return
    end
    b.ai = Agent.idle(agent)
    offerAgent(b)
    autoGenerate(b, cx)
    cx:render()
    AgentHost.listModels(agent, function(models)
     agent.models = models
     cx:render()
    end)
   end)
   -- A directory that is no checkout still opens a PR link.
   local function found(repo: Fetch.Repo?, err: string?)
    b.repo = repo
    if repo or Links.linkRepo(pr) then
     openPr(b, cx, pr)
    else
     b.notice = Notice.failed(b.name, err or "A PR number needs a checkout to read it from.")
    end
    cx:render()
   end
   if dir == "" then found(nil, nil) else Fetch.findRepo(dir, found) end
  end)
  return b
 end,
 title = function(b: Block): string?
  if b.page then return "Review · #" .. b.page.review.pr.number end
  return if b.name ~= "" then "PR " .. b.name else "PR Guide"
 end,
 view = function(b: Block): BlockView
  local s = b.page
  if not s then
   return { main = Notice.view(b.notice) }
  end
  s.now = Host.time()
  local motion = { born = s.born, next = {}, booted = s.booted, animate = not s.keyed }
  local main = Page.view(s, motion)
  s.born, s.booted = motion.next, true
  return { main = main, layer = Page.layer(s) }
 end,
 event = function(b: Block, ev: UiEvent, cx: BlockCx)
  local action = actionOf(b, ev)
  if not action then return end
  if b.page then b.page.keyed = false end
  if action.act == "generate-guide" then
   generate(b, cx)
  elseif b.page then
   dispatch(b.page, cx, action)
   remember(b, b.page)
  end
 end,
 key = function(b: Block, key: Key, cx: BlockCx): boolean?
  local s = b.page
  if not s then return false end
  local action = Keys.action(s, key)
  if action then
   s.keyed = true
   if action.act == "generate-guide" then generate(b, cx) else dispatch(s, cx, action) end
   remember(b, s)
   return true
  end
  local field = State.field(s)
  if field then
   local next = Keys.afterTyping(State.mode(s), Fields.key(field, key))
   if next then
    s.keyed = true
    dispatch(s, cx, next)
   end
   return true
  end
  -- Panels swallow the keys they don't use.
  return State.mode(s) ~= "reading"
 end,
}

return block
