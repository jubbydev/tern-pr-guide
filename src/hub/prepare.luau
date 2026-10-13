--!strict
-- Prepares AI guides in the background while Settings say so: after a refresh, and once on start, each review requested
-- of the viewer whose saved guide is missing or was written for another head is explained by the reader's agent, one at
-- a time, so the guide is there when the PR opens. Explanation only, never the review. Nothing shows on the board.
local Agent = require("../agent")
local AgentHost = require("../agent-host")
local Fetch = require("../fetch")
local Host = require("../host")
local Model = require("./model")
local Platform = require("../platform")
local Prdata = require("../prdata")
local Runtime = require("./runtime")

type Block = Runtime.Block

-- One block's preparing: whether a PR is being prepared, whether a refresh asked for another pass meanwhile, the PRs
-- (by key and head) tried this session, success or not, and each repo's checkout once looked for (false: none).
type Run = { running: boolean, again: boolean, tried: { [string]: boolean }, checkouts: { [string]: Fetch.Repo | false } }

-- Who is preparing which PR, shared by every hub window, so two windows don't explain the same PR at once.
local KV_LEASE = "hub.preparing"
-- A lease older than an agent run's timeout is left over from a window that closed mid-run.
local LEASE_SECONDS = 20 * 60

local M = {}

local runs: { [Block]: Run } = setmetatable({}, { __mode = "k" }) :: any

local function triedKey(pr: Model.HubPR): string
	return pr.key .. "@" .. pr.headOid
end

-- The PRs that may want a guide: review requests of the viewer not yet tried at their head this session, in board order.
function M.candidates(prs: { Model.HubPR }, tried: { [string]: boolean }): { Model.HubPR }
	local out = {}
	for _, pr in prs do
		if pr.reviews.requestedMe and not tried[triedKey(pr)] then table.insert(out, pr) end
	end
	return out
end

-- Whether `pr` needs a guide, given the head its saved guide was written against (nil: no guide).
function M.needsGuide(guideHead: string?, pr: Model.HubPR): boolean
	return guideHead ~= pr.headOid
end

-- Takes the lease on `pr` unless another window holds a live one on it. ponytail: read then write, so two windows
-- deciding in the same instant can both take it; a lease only narrows the overlap to that instant.
local function lease(pr: Model.HubPR, now: number): boolean
	local ok, held = pcall(Host.kv.get, KV_LEASE)
	if ok and type(held) == "table" and held.key == triedKey(pr) and type(held.at) == "number" and now - held.at < LEASE_SECONDS then
		return false
	end
	pcall(Host.kv.set, KV_LEASE, { key = triedKey(pr), at = now })
	return true
end

local function release(pr: Model.HubPR)
	local ok, held = pcall(Host.kv.get, KV_LEASE)
	if ok and type(held) == "table" and held.key == triedKey(pr) then pcall(Host.kv.set, KV_LEASE, nil) end
end

-- A checkout of `slug` beside the hub's folder, else PR Guide's own copy (as opening a PR finds one), looked for once.
local function checkout(run: Run, cx: BlockCx, slug: string, done: (Fetch.Repo?) -> ())
	local known = run.checkouts[slug]
	if known ~= nil then return done(if known then known else nil) end
	Fetch.checkoutFor(nil, cx.cwd or Platform.home() or "", slug, function(found)
		local repo = found or Fetch.savedCopy("github.com", slug)
		run.checkouts[slug] = repo or false
		done(repo)
	end)
end

local function going(b: Block): boolean
	return not b.closed and b.agent ~= nil and b.s.prepareGuides
end

-- Prepares the PRs `queue` holds from `i` on, then looks again if a refresh asked meanwhile.
local function prepare(b: Block, cx: BlockCx, run: Run, queue: { Model.HubPR }, i: number)
	local pr = queue[i]
	if not pr or not going(b) then
		run.running = false
		if run.again and going(b) then M.run(b, cx) end
		return
	end
	local function nextOne() prepare(b, cx, run, queue, i + 1) end
	if run.tried[triedKey(pr)] then return nextOne() end
	run.tried[triedKey(pr)] = true
	checkout(run, cx, pr.repo, function(repo)
		if not repo or not going(b) or not M.needsGuide(Fetch.guideHead(repo, pr.number), pr) then return nextOne() end
		if not lease(pr, Host.time()) then return nextOne() end
		Prdata.openPr({ pr = tostring(pr.number), repo = repo.root, cache = repo.cache }, function() end, function(loaded)
			if not loaded or not going(b) then
				release(pr)
				return nextOne()
			end
			-- A review page may have picked another explanation model since the hub found its agent.
			AgentHost.refreshChoice(b.agent :: Agent.Agent)
			AgentHost.explain(b.agent :: Agent.Agent, repo, loaded, function()
				release(pr)
				nextOne()
			end)
		end)
	end)
end

-- Starts preparing the board's review requests, or, while a PR is being prepared, asks for another look once it ends.
function M.run(b: Block, cx: BlockCx)
	if b.fixture or not going(b) then return end
	local run = runs[b]
	if not run then
		run = { running = false, again = false, tried = {}, checkouts = {} }
		runs[b] = run
	end
	if run.running then
		run.again = true
		return
	end
	run.running, run.again = true, false
	prepare(b, cx, run, M.candidates(b.s.prs, run.tried), 1)
end

return M
