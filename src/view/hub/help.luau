--!strict
-- The `?` panel: every key the hub answers to, in the order a session goes: move, act on a card, run the board.
local Paths = require("./paths")
local Ui = require("../ui")

local el, span = Ui.el, Ui.span

type Group = { title: string, keys: { { string } } } -- a key row is { keys, label, keys on a second line? }

local GROUPS: { Group } = {
	{ title = "Move", keys = {
		{ "h j k l", "Move between cards", "← ↑ ↓ →" },
		{ "⏎", "Open the card, fixes page, or a Fix ready card for review" },
		{ "⇧⏎", "Open with the AI guide started" },
		{ ".", "Next pull request that needs you" },
		{ "T", "Switch tab" },
		{ "I", "Show or hide Inactive" },
		{ "⇧T", "Show or hide Team requests" },
		{ "A", "Show or hide Approved, on Review requests" },
		{ "R", "Show or hide Recently merged, or Recently opened on Review requests" },
	} },
	{ title = "The selected card", keys = {
		{ "A", "Fix with agent, Hand off to Tandem, Stop, Try again, Clone repo, or Summarize" },
		{ "O", "Choose folder, or open a failed fix's worktree" },
		{ "⇧A", "Summarize feedback, or Return worktree on a Tandem card with a failed fix" },
		{ "C", "Copy link" },
		{ "M", "Merge (⌘⏎ confirms), Merge when ready, or Cancel merge" },
		{ "Q", "Re-request review from who is waiting on a re-review" },
		{ "U", "Update branch" },
		{ "⇧R", "Re-run failed checks" },
		{ ",", "Merge method" },
		{ "X", "Remove from Review requests" },
	} },
	{ title = "The fixes page", keys = {
		{ "j k", "Next or previous step, or action" },
		{ "h l", "Between the steps and the code", "← →" },
		{ "⏎", "Go to the code, or choose" },
		{ "R", "Reply to the thread (⌘⏎ posts)" },
		{ "E", "Resolve the thread" },
		{ "⇧L", "View the check's log" },
		{ "⇧R", "Re-run failed checks" },
		{ "G", "Open on GitHub, or resolve a conflict there" },
		{ "B", "Show or hide bot comments" },
		{ "Esc", "Back to the board" },
	} },
	{ title = "The board", keys = {
		{ "/", "Search" },
		{ "N", "Add a pull request by link" },
		{ "F", "Filter by repository" },
		{ "S", "Sort" },
		{ "⇧S", "Settings: models, effort, lens and where links open (also ⇧M)" },
		{ "⌘R", "Refresh" },
		{ "j k", "Move in a menu" },
		{ "Space", "Select a card to merge or close, or choose in a menu" },
		{ "⇧X", "Select stale pull requests to close" },
		{ "M X", "Merge or close the selected cards (⌘⏎ confirms)" },
		{ "⌘⏎", "Confirm a question" },
		{ "Esc", "Clear, cancel or close" },
		{ "?", "All shortcuts" },
	} },
	{ title = "Review fix", keys = {
		{ "j k", "Next or previous conflict", "↑ ↓" },
		{ "⏎", "Mark the conflict reviewed or unreviewed" },
		{ "B", "Switch between the resolution and original conflict" },
		{ "P", "Push after every conflict is reviewed, or retry lease return" },
		{ "D", "Discard fix (⌘⏎ or Ctrl+Enter confirms)" },
		{ "Esc", "Cancel Discard, or return to the board" },
	} },
}

local M = {}

function M.view(): Node
	local cols: { Node } = {}
	for _, group in GROUPS do
		local rows: { Node } = { span("gp-panel-h", group.title) }
		for _, key in group.keys do
			local caps: { Node } = { Ui.keys(key[1]) }
			if key[3] then table.insert(caps, Ui.keys(key[3])) end
			local row: { Node } = { el("span", { class = "gp-hh-keys" }, caps), span("gp-keylabel", key[2]) }
			table.insert(rows, el("div", { class = "gp-keyrow" }, row))
		end
		table.insert(cols, el("div", { class = "gp-keycol" }, rows))
	end
	local body = el("div", { class = "gp-hh", key = "body" }, cols)
	return { k = "overlay", p = { key = "help", role = "gp.hubhelp", aria = "All shortcuts", anchor = { node = Paths.titleLabel, side = "below" }, size = "lg" }, c = { body } } :: any
end

return M
