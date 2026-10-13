--!strict
local Fields = require("../src/text-field")
local Model = require("../src/hub/model")
local Keys = require("../src/keys")
local State = require("../src/hub/state")
local Cases: any = require("../fixtures/hub/cases")

local NOW: number = Cases.asOf
local SORTS = { "repository", "priority", "newest", "oldest", "smallest" }

local function join(list: { string }): string
	return table.concat(list, ",")
end

local function keysOf(cards: { State.Card }): { string }
	local out = {}
	for _, card in cards do table.insert(out, card.pr.key) end
	return out
end

local function column(s: State.State, id: string): { string }
	for _, entry in s.board.columns do
		if entry.column == id then return keysOf(entry.cards) end
	end
	error("no column " .. id)
end

-- The keys in the card fold `id` under the tab's board.
local function fold(s: State.State, id: string): { string }
	local found = State.fold(s, id :: any)
	if not found then error("no fold " .. id) end
	return keysOf(found.cards)
end

local function foldOpen(s: State.State, id: string): boolean
	local found = State.fold(s, id :: any)
	return found ~= nil and found.open
end

-- The PR with `key` in `s`, mutable.
local function byKey(s: State.State, key: string): Model.HubPR
	for _, pr in s.prs do
		if pr.key == key then return pr end
	end
	error("no PR " .. key)
end

local function copy(value: any): any
	if type(value) ~= "table" then return value end
	local out = {}
	for k, v in value do out[k] = copy(v) end
	return out
end

-- A state over its own copy of the cases, so a test that changes a PR leaves the fixture alone.
local function fresh(saved: any?): State.State
	return State.new(copy(Cases.prs), NOW, saved)
end

local roleOf: { [string]: string } = {}
for _, pr in Cases.prs do roleOf[pr.key] = pr.role end

return function()
	-- Every fixture key lands in its expected column and order, for each sort and both tabs.
	for _, sort in SORTS do
		local expected = Cases.orders[sort]
		for _, tab in { "mine", "review" } do
			local s = fresh({ tab = tab, sort = sort })
			assert(s.board.tab == tab and s.sort == sort)
			for _, entry in s.board.columns do
				local want = join(expected[entry.column])
				assert(join(keysOf(entry.cards)) == want, sort .. "/" .. entry.column .. ": " .. join(keysOf(entry.cards)))
				for _, card in entry.cards do
					assert(card.column == entry.column and Cases.columns[card.pr.key] == entry.column)
				end
			end
			local folds = {}
			for _, entry in s.board.folds do
				table.insert(folds, entry.column)
				-- A fold holds the column's cards from this tab only.
				local want = {}
				for _, key in expected[entry.column] do
					if roleOf[key] == tab then table.insert(want, key) end
				end
				assert(join(keysOf(entry.cards)) == join(want), sort .. "/" .. tab .. "/" .. entry.column .. ": " .. join(keysOf(entry.cards)))
			end
			assert(join(folds) == (if tab == "mine" then "inactive" else "inactive,team,approved"), "folds under " .. tab)
		end
	end

	-- Smallest first orders by additions + deletions (literal expectations).
	local smallest = fresh({ tab = "mine", sort = "smallest" })
	assert(join(column(smallest, "in_review")) == "acme/api#107,acme/api#106,acme/api#120,acme/api#121,acme/api#114,acme/api#115")
	assert(column(smallest, "needs_fixes")[1] == "acme/mono#201")

	-- Defaults, and the grid that h j k l walk.
	local s = fresh()
	assert(s.tab == "mine" and s.sort == "repository" and s.repositories == nil and s.mode == "board" and s.selected == nil)
	assert(#s.board.grid == 3 and join(s.board.grid[3]) == "acme/api#110,acme/api#108,acme/api#109")
	assert(#s.board.grid[1] == 15 and #s.board.columns[1].cards == 15)
	assert(s.board.empty == false)
	assert(foldOpen(s, "inactive") == false, "Inactive starts folded")
	assert(s.board.counts.mine == 15 and s.board.counts.review == 5, "blue counts are the your-turn columns")
	assert(State.mode(s) == "board")
	for _, card in s.board.columns[1].cards do assert(card.selected == false and card.main ~= nil) end

	-- Tab transitions: counts stay, columns and selection follow the tab.
	State.select(s, "acme/api#116")
	State.switchTab(s)
	assert(s.tab == "review" and s.board.tab == "review" and s.selected == nil)
	assert(join(column(s, "to_review")) == join(Cases.orders.repository.to_review))
	assert(s.board.counts.mine == 15 and s.board.counts.review == 5)
	assert(join(fold(s, "inactive")) == "acme/web#310" and join(fold(s, "team")) == "acme/web#309")
	assert(join(fold(s, "approved")) == "acme/web#306,acme/web#302" and #s.board.columns == 2)
	assert(not foldOpen(s, "inactive") and not foldOpen(s, "team") and not foldOpen(s, "approved"), "every fold starts folded")
	State.switchTab(s)
	assert(s.tab == "mine")
	State.setTab(s, "mine")
	assert(s.tab == "mine")

	-- Sort transitions.
	State.setSort(s, "smallest")
	assert(s.sort == "smallest" and column(s, "ready")[1] == "acme/api#109")
	State.setSort(s, "repository")
	assert(column(s, "ready")[1] == "acme/api#110")

	-- Repository filter: toggling narrows both the board and the counts; clearing restores.
	State.toggleRepository(s, "acme/api")
	assert(join(column(s, "needs_fixes")) == "acme/api#116,acme/api#118,acme/api#119,acme/api#105,acme/api#112")
	assert(s.board.counts.mine == 5 and s.board.counts.review == 2)
	assert(join(fold(s, "inactive")) == "acme/api#122")
	assert(s.repositories ~= nil and (s.repositories :: any)["acme/api"] == true)
	State.toggleRepository(s, "acme/web")
	assert(s.board.counts.mine == 9)
	State.toggleRepository(s, "acme/web")
	State.toggleRepository(s, "acme/api")
	assert(s.repositories == nil and s.board.counts.mine == 15)
	State.toggleRepository(s, "acme/web")
	State.clearRepositories(s)
	assert(s.repositories == nil and #s.board.columns[1].cards == 15)
	-- The repository options: most pull requests first, ties by name.
	assert(s.board.repositories[1].repo == "acme/mono" and s.board.repositories[1].count == 16)
	assert(s.board.repositories[2].repo == "acme/api" and s.board.repositories[2].count == 15)
	assert(s.board.repositories[3].repo == "acme/web" and s.board.repositories[3].count == 6)

	-- Search: live, over "#n", title and repo; it opens Inactive for its matches and drops a selection it hides.
	State.select(s, "acme/api#116")
	State.setSearch(s, "#101")
	assert(join(column(s, "needs_fixes")) == "acme/web#101" and #column(s, "in_review") == 0)
	assert(s.selected == nil, "selection follows its card off the board")
	assert(s.board.counts.mine == 1 and s.board.counts.review == 0)
	State.setSearch(s, "acme/mono")
	assert(#column(s, "needs_fixes") == 6 and foldOpen(s, "inactive") and #fold(s, "inactive") == 10)
	State.setSearch(s, "nothing matches this")
	assert(s.board.empty == true)
	State.setSearch(s, "")
	assert(s.board.empty == false and foldOpen(s, "inactive") == false)

	-- Search mode: typing is the search field's; Esc clears, Enter keeps the text.
	State.openSearch(s)
	assert(s.mode == "search")
	State.setSearch(s, "case 3")
	State.closeSearch(s, false)
	assert(s.mode == "board" and s.search.text == "case 3")
	State.openSearch(s)
	State.closeSearch(s, true)
	assert(s.mode == "board" and s.search.text == "" and #s.board.columns[1].cards == 15)

	-- Moving: nothing selected starts at the first card; columns keep their row; Inactive is entered from below.
	assert(State.move(s, "left") and s.selected == "acme/api#116")
	assert(State.move(s, "left") == false)
	assert(State.move(s, "up") == false and State.onTopRow(s))
	assert(State.move(s, "down") and s.selected == "acme/api#118" and not State.onTopRow(s))
	assert(State.selectedCard(s) ~= nil and (State.selectedCard(s) :: State.Card).selected)
	assert(State.move(s, "up") and s.selected == "acme/api#116")
	assert(State.move(s, "right") and s.selected == "acme/api#114")
	assert(State.move(s, "right") and s.selected == "acme/api#110")
	assert(State.move(s, "right") == false)
	assert(State.move(s, "down") and State.move(s, "down") and s.selected == "acme/api#109")
	assert(State.move(s, "down") == false, "Inactive is folded")
	State.toggleFold(s, "inactive")
	assert(foldOpen(s, "inactive") and s.folded.inactive == false)
	assert(s.selected == "acme/api#122", "opening a fold selects its first row")
	assert(State.move(s, "down") and s.selected == "acme/mono#216")
	assert(State.move(s, "up") and State.move(s, "up") and s.selected == "acme/web#104", "up from Inactive returns to the board")
	-- Right from a short row clamps to the last card of the next column.
	State.select(s, "acme/web#104")
	assert(State.move(s, "right") and s.selected == "acme/api#107")

	-- Menus.
	State.openMenu(s, "sort")
	assert(s.mode == "menu" and s.menu == "sort" and s.menuCursor == 1)
	local rows = State.menuRows(s)
	assert(#rows == 5 and rows[5].label == "Smallest first" and rows[1].on and not rows[5].on)
	State.menuMove(s, 1)
	State.menuMove(s, 10)
	assert(s.menuCursor == 5)
	State.menuMove(s, -10)
	assert(s.menuCursor == 1)
	assert(State.menuPick(s, 5) == true)
	assert(s.sort == "smallest" and s.menu == nil and s.mode == "board")
	State.openMenu(s, "sort")
	assert(s.menuCursor == 5, "the menu opens on the current choice")
	State.closeMenu(s)
	State.openMenu(s, "repositories")
	rows = State.menuRows(s)
	assert(#rows == 3 and rows[1].label == "mono" and rows[1].count == 16 and rows[1].kind == "check")
	assert(State.menuPick(s, 2) == false and s.menu == "repositories", "a repository toggles and the menu stays")
	assert(s.repositories ~= nil and (s.repositories :: any)["acme/api"] == true)
	rows = State.menuRows(s)
	assert(#rows == 4 and rows[4].kind == "clear")
	assert(State.menuPick(s, 4) == true and s.repositories == nil and s.menu == nil)
	State.openMenu(s, "settings")
	assert(#State.menuRows(s) == 0, "no agent found: no rows")
	State.closeMenu(s)

	State.openMenu(s, "settings")
	assert(s.models == nil, "no agent found: no model menu")
	-- Where links open: L flips it, a click sets one side.
	assert(s.links == "tern")
	State.setLinks(s)
	assert(s.links == "browser")
	State.setLinks(s, "browser")
	assert(s.links == "browser")
	State.setLinks(s, "tern")
	assert(s.links == "tern")
	State.closeMenu(s)

	-- Help.
	State.openHelp(s)
	assert(s.mode == "help" and s.menu == nil)
	State.closeHelp(s)
	assert(s.mode == "board")

	-- What is saved comes back, and a bad save is ignored.
	State.setSort(s, "oldest")
	State.toggleRepository(s, "acme/web")
	State.setTab(s, "review")
	local saved = State.saved(s)
	assert(saved.tab == "review" and saved.sort == "oldest" and join(saved.repositories :: { string }) == "acme/web")
	local back = fresh(saved)
	assert(back.tab == "review" and back.sort == "oldest" and (back.repositories :: any)["acme/web"] == true)
	assert(join(column(back, "to_review")) == "acme/web#311,acme/web#303,acme/web#301")
	local bad = fresh({ tab = "x", sort = 3, repositories = "no", folded = { inactive = "no" } })
	assert(bad.tab == "mine" and bad.sort == "repository" and bad.repositories == nil and bad.folded.inactive == true)
	assert(fresh(nil).tab == "mine" and #State.new({}, NOW, nil).board.columns[1].cards == 0 and State.new({}, NOW, nil).board.empty)

	-- Card actions follow the spec's table.
	local cards = fresh().board
	local function mainOf(key: string, tab: string?): string
		local card = State.card(fresh({ tab = tab or "mine" }), key)
		assert(card ~= nil, key)
		return ((card :: State.Card).main or { label = "none" }).label
	end
	assert(cards.columns[1].cards[1].main and (cards.columns[1].cards[1].main :: State.CardAction).label == "Fix with agent")
	assert(mainOf("acme/api#114") == "Copy link" and mainOf("acme/api#110") == "Merge" and mainOf("acme/web#301", "review") == "Review")
	assert(mainOf("acme/api#122") == "none" and mainOf("acme/web#306", "review") == "none")
	assert(State.card(fresh(), "acme/api#103") == nil)
	local fixes = State.card(fresh(), "acme/web#103") :: State.Card
	assert(fixes.main and fixes.main.label == "Fix with agent" and fixes.main.key == "A" and #fixes.more == 1
		and fixes.more[1].label == "Summarize" and fixes.more[1].key == "⇧A", "a requested change: A fixes, ⇧A summarizes")
	local comments = State.card(fresh(), "acme/api#119") :: State.Card
	assert(comments.main and comments.main.label == "Summarize" and comments.main.key == "A" and #comments.more == 0, "comments alone: A summarizes")
	local both = State.card(fresh(), "acme/api#116") :: State.Card
	assert(both.main and both.main.label == "Fix with agent" and #both.more == 2 and both.more[1].key == "⇧A" and both.more[2].label == "Re-run failed checks" and both.more[2].key == "⇧R")
	local added = State.card(fresh({ tab = "review" }), "acme/web#303") :: State.Card
	assert(added.main and added.main.label == "Review" and #added.more == 1 and added.more[1].label == "Remove from Review requests")

	-- Chip lines: one chip per job, then the first job's detail.
	local function chipsOf(key: string, tab: string?): (string, string?)
		local card = State.card(fresh({ tab = tab or "mine" }), key) :: State.Card
		local names = {}
		for _, chip in card.chips do table.insert(names, chip.text) end
		return join(names), card.detail
	end
	local names, detail = chipsOf("acme/api#116")
	assert(names == "Merge failed,Address changes,Fix checks,Resolve conflicts" and detail == "Removed from the merge queue: a required check failed")
	names, detail = chipsOf("acme/api#119")
	assert(names == "Reply" and detail == "1 unresolved comment")
	names, detail = chipsOf("acme/web#103")
	assert(names == "Address changes" and detail == "Changes requested by @bob")
	names, detail = chipsOf("acme/api#105")
	assert(names == "Resolve conflicts" and detail == "Conflicts with main")
	names, detail = chipsOf("acme/web#104")
	assert(names == "Fix checks" and detail == "1/4 checks failing")
	names, detail = chipsOf("acme/web#301", "review")
	assert(names == "Review" and detail == "@maria-k asked 2h ago")
	names, detail = chipsOf("acme/web#311", "review")
	assert(names == "Re-review" and detail == "Requested again")
	names, detail = chipsOf("acme/api#307", "review")
	assert(names == "Re-review" and detail == "Requested again", "asked again after a comment")
	-- An approval that new commits passed stays in Approved with a quiet note; one on the head has none.
	local stale302 = State.card(fresh({ tab = "review" }), "acme/web#302") :: State.Card
	assert(stale302.column == "approved" and #stale302.chips == 0 and stale302.note == "New commits since you approved")
	assert((State.card(fresh({ tab = "review" }), "acme/web#306") :: State.Card).note == nil)
	names, detail = chipsOf("acme/web#303", "review")
	assert(names == "Review" and detail == "Added by you")
	names, detail = chipsOf("acme/web#304", "review")
	assert(names == "You requested changes" and detail == nil)
	names = chipsOf("acme/web#305", "review")
	assert(names == "You commented")
	names = chipsOf("acme/api#114")
	assert(names == "Waiting on checks")
	names = chipsOf("acme/api#106")
	assert(names == "Waiting on review")
	names = chipsOf("acme/api#110")
	assert(names == "", "done cards have no chip line")
	-- Recently opened: a fold under Review requests only, closed to start, newest first, narrowed by the search.
	local recent: { State.Opened } = {
		{ repo = "acme/api", number = 9, title = "Add retries", author = "dana", at = "2026-10-08T09:12:33Z" },
		{ repo = "acme/web", number = 4, title = "Move tabs", author = "ruben", at = "2026-10-07T09:12:33Z" },
	}
	local rs = fresh({ tab = "review" })
	State.setRecent(rs, recent)
	assert(#rs.board.recent == 2 and not rs.board.open.recent)
	assert(State.move(rs, "down") and rs.selected ~= nil and State.recentRow(rs, rs.selected) == nil)
	State.toggleFold(rs, "recent")
	assert(rs.board.open.recent and State.recentKey(recent[1]) == "rc:acme/api#9")
	assert(rs.selected == "rc:acme/api#9", "opening the row fold selects its first row")
	State.select(rs, "rc:acme/web#4")
	local picked = State.selectedRecent(rs)
	assert(picked and picked.number == 4 and State.selectedCard(rs) == nil)
	State.setSearch(rs, "retries")
	assert(#rs.board.recent == 1 and rs.board.recent[1].number == 9 and rs.selected == nil)
	State.setSearch(rs, "")
	-- down from the last card of the last column walks into the fold, rows in order
	local last = fresh({ tab = "review" })
	State.setRecent(last, recent)
	State.toggleFold(last, "recent")
	local lastKeys = last.board.grid[#last.board.grid]
	for _, keys in last.board.grid do
		if #keys > 0 then lastKeys = keys end
	end
	State.select(last, lastKeys[#lastKeys])
	assert(State.move(last, "down") and last.selected == "rc:acme/api#9")
	assert(State.move(last, "down") and last.selected == "rc:acme/web#4")
	assert(not State.move(last, "down") and last.selected == "rc:acme/web#4")
	assert(State.move(last, "up") and last.selected == "rc:acme/api#9")
	-- Your pull requests ends with Recently merged instead: the last 7 days of the cache's list, under its own fold name.
	local mine = fresh({ tab = "mine" })
	State.setRecent(mine, recent)
	assert(#mine.board.recent == 0 and not mine.board.open.recent)
	State.setMerged(mine, {
		{ repo = "acme/web", number = 981, title = "Cache sprites", author = "", at = "2026-10-09T00:00:00Z" },
		{ repo = "acme/api", number = 377, title = "Log slow queries", author = "", at = "2026-09-01T00:00:00Z" },
	})
	assert(#mine.board.recent == 1 and mine.board.recent[1].number == 981 and not mine.board.open.recent)
	State.toggleFold(mine, "recent")
	assert(not mine.board.open.recent, "Recently opened's flag doesn't open Recently merged")
	State.toggleFold(mine, "merged")
	assert(mine.board.open.recent)
	State.setTab(mine, "review")
	assert(#mine.board.recent == 2 and mine.board.recent[1].number == 9, "Review requests keeps Recently opened")
	State.setMerged(mine, nil)
	State.setTab(mine, "mine")
	assert(#mine.board.recent == 0)

	-- Card actions: Merge asks first, naming the repo's method; ⌘⏎ is the block's, Esc cancels.
	local ms = fresh()
	assert(State.mergeMethodFor(ms, byKey(ms, "acme/api#110")) == "squash", "no detected method: squash")
	assert(State.askMerge(ms, "acme/api#110") and ms.mode == "confirm" and ms.selected == "acme/api#110")
	local asked = State.card(ms, "acme/api#110") :: State.Card
	assert(asked.asking == "Squash and merge #110?" and State.card(ms, "acme/api#108") :: any and (State.card(ms, "acme/api#108") :: State.Card).asking == nil)
	State.cancelConfirm(ms)
	assert(ms.mode == "board" and ms.confirm == nil and (State.card(ms, "acme/api#110") :: State.Card).asking == nil)
	ms.merges["acme/api"] = { method = { kind = "rebase" }, source = "user", ask = false }
	State.askMerge(ms, "acme/api#110")
	assert((State.card(ms, "acme/api#110") :: State.Card).asking == "Rebase and merge #110?")
	State.select(ms, "acme/api#108")
	assert(ms.confirm == nil and ms.mode == "board", "choosing another card drops the question")
	ms.merges["acme/api"] = { method = { kind = "queue" }, source = "user", ask = false }
	assert(State.mergeMethodFor(ms, byKey(ms, "acme/api#110")) == "squash", "a queue method is not merged by GitHub's merge")
	assert(not State.askMerge(ms, "acme/web#103"), "only Merge cards ask")
	State.setBusy(ms, "acme/api#110", "Merging…")
	assert(not State.askMerge(ms, "acme/api#110") and (State.card(ms, "acme/api#110") :: State.Card).busy == "Merging…")
	State.dropPr(ms, "acme/api#110")
	assert(State.card(ms, "acme/api#110") == nil and ms.busy["acme/api#110"] == nil)

	-- Update branch: the card waits on its checks afterwards.
	local us = fresh()
	local behind = byKey(us, "acme/api#110")
	behind.behind = true
	State.project(us)
	local upd = State.card(us, "acme/api#110") :: State.Card
	assert(upd.main and upd.main.label == "Update branch" and upd.main.key == "U" and upd.column == "ready")
	State.branchUpdated(us, "acme/api#110")
	upd = State.card(us, "acme/api#110") :: State.Card
	assert(behind.behind == false and behind.checks.state == "pending" and upd.column ~= "ready")

	-- Add by link: what the field's text names.
	local ls = fresh({ tab = "review" })
	local function target(text: string): State.LinkTarget
		ls.link = Fields.create(text)
		return State.linkTarget(ls)
	end
	assert(target("").kind == "empty" and target("   ").kind == "empty")
	assert(target("hello").kind == "invalid" and target("123").kind == "invalid" and target("https://example.com/a/b/pull/3").kind == "invalid")
	assert(target("https://gitlab.com/acme/api/pull/3").kind == "invalid")
	for _, form in { "github.com/acme/new/pull/77", "https://github.com/acme/new/pull/77", "http://www.github.com/acme/new/pull/77", "www.github.com/acme/new/pull/77/files", "GitHub.com/acme/new/pull/77", "acme/new#77" } do
		local t = target(form) :: any
		assert(t.kind == "new" and t.repo == "acme/new" and t.number == 77, form)
	end
	assert((target("github.com/ACME/web/pull/301") :: any).kind == "board")
	for _, form in { "gitlab.com/acme/new/pull/77", "https://notgithub.com/acme/new/pull/77", "github.com.evil.io/acme/new/pull/77", "https://github.com/acme/new/issues/77" } do
		assert(target(form).kind == "invalid", form)
	end
	local fresh1 = target("https://github.com/acme/new/pull/77/files") :: any
	assert(fresh1.kind == "new" and fresh1.repo == "acme/new" and fresh1.number == 77)
	fresh1 = target("acme/new#78") :: any
	assert(fresh1.kind == "new" and fresh1.repo == "acme/new" and fresh1.number == 78)
	local known = target("  https://github.com/ACME/web/pull/301  ") :: any
	assert(known.kind == "board" and known.pr.key == "acme/web#301" and known.repo == "acme/web")
	assert((target("acme/web#0") :: any).kind == "invalid")
	-- A review request folded away from To review is offered to add, from either fold; one in To review is shown.
	local team = target("https://github.com/acme/web/pull/309") :: any
	assert(team.kind == "folded" and team.column == "team" and team.pr.key == "acme/web#309")
	local stale = target("acme/web#310") :: any
	assert(stale.kind == "folded" and stale.column == "inactive")
	assert((target("acme/api#122") :: any).kind == "board", "the viewer's own Inactive PR is only shown")
	-- Adding it moves it into To review, which counts it.
	State.markAdded(ls, "acme/web#309")
	assert(table.find(column(ls, "to_review"), "acme/web#309") and #fold(ls, "team") == 0 and ls.board.counts.review == 6)
	assert((target("acme/web#309") :: any).kind == "board")
	-- Removing it again folds it back: the team's request still stands, so it stays on the board.
	State.unadd(ls, "acme/web#309")
	assert(join(fold(ls, "team")) == "acme/web#309" and ls.board.counts.review == 5)

	-- Team requests: folded by default, outside the count and Next up, with a quiet chip naming the team.
	local ts = fresh({ tab = "review" })
	assert(ts.board.counts.review == 5 and not table.find(column(ts, "to_review"), "acme/web#309"))
	for _, item in Model.queue(ts.prs, NOW) do assert(item.key ~= "acme/web#309") end
	assert(State.card(ts, "acme/web#309") ~= nil and not foldOpen(ts, "team"))
	State.move(ts, "down")
	for _ = 1, 10 do State.move(ts, "down") end
	assert(ts.selected ~= "acme/web#309", "a folded card isn't reached by j")
	local teamCard = State.card(ts, "acme/web#309") :: State.Card
	assert(#teamCard.chips == 1 and teamCard.chips[1].text == "Requested from @acme/web-platform" and teamCard.chips[1].kind == "wait")
	assert(teamCard.main == nil and #teamCard.more == 0)
	local ok, why = State.toggleMark(ts, "acme/web#309")
	assert(not ok and why == "review requests can't be selected" and next(ts.marked) == nil)
	State.toggleFold(ts, "team")
	assert(foldOpen(ts, "team") and ts.folded.team == false and State.saved(ts).folded.team == false)
	assert(State.new(copy(Cases.prs), NOW, State.saved(ts)).folded.team == false, "the fold's state is saved")
	State.toggleFold(ts, "team")
	State.setSearch(ts, "design tokens")
	assert(foldOpen(ts, "team") and join(fold(ts, "team")) == "acme/web#309", "a search opens the fold on its matches")
	State.setSearch(ts, "")
	-- Walking or showing a card in a fold opens that fold.
	assert(State.show(ts, "acme/web#309") and foldOpen(ts, "team") and ts.selected == "acme/web#309")

	-- Inactive on Review requests: the stale request, its chip, and nothing that selects or closes it.
	local ri = fresh({ tab = "review" })
	local staleCard = State.card(ri, "acme/web#310") :: State.Card
	assert(staleCard.column == "inactive" and staleCard.chips[1].text == "No recent activity")
	assert(not State.toggleMark(ri, "acme/web#310") and next(ri.marked) == nil)
	assert(State.staleCount(ri) == 0 and State.markStale(ri) == 0 and next(ri.marked) == nil)
	State.toggleFold(ri, "inactive")
	assert(join(fold(ri, "inactive")) == "acme/web#310" and State.staleCount(ri) == 0)
	assert(not State.askBatch(ri, "inactive"))
	-- A Close stale selection on the viewer's tab doesn't follow to Review requests.
	local both = fresh({ tab = "mine" })
	assert(State.markStale(both) > 0)
	State.toggleFold(both, "inactive")
	assert(next(both.marked) == nil, "closing the fold drops the marks in it")
	assert(State.markStale(both) > 0)
	State.setTab(both, "review")
	assert(next(both.marked) == nil and State.selection(both) == nil)

	-- Keys: ⇧T toggles Team requests on Review requests only; I toggles Inactive on both tabs.
	local function pressed(st: State.State, name: string, shift: boolean): any
		return Keys.hubAction(st, { name = name, shift = shift, meta = false, ctrl = false, alt = false } :: any)
	end
	local keyed = fresh({ tab = "review" })
	local shiftT = pressed(keyed, "t", true)
	assert(shiftT and shiftT.act == "hub-fold" and shiftT.value == "team")
	assert(pressed(keyed, "i", false).value == "inactive")
	State.setTab(keyed, "mine")
	assert(pressed(keyed, "i", false).value == "inactive")
	local mineShiftT = pressed(keyed, "t", true)
	assert(mineShiftT == nil or mineShiftT.value ~= "team")
	-- A toggles Approved on Review requests, even with a card selected; on Your pull requests it stays the card's key.
	local keyedA = fresh({ tab = "review" })
	State.select(keyedA, "acme/web#301")
	local a = pressed(keyedA, "a", false)
	assert(a and a.act == "hub-fold" and a.value == "approved")
	local mineA = fresh()
	State.select(mineA, "acme/web#103")
	local fixA = pressed(mineA, "a", false)
	assert(fixA and fixA.act == "card-agent" and fixA.value == "acme/web#103")

	-- N opens the field on Review requests; choosing a card leaves it; Esc empties it.
	local ns = fresh()
	State.openLink(ns)
	assert(ns.tab == "review" and ns.mode == "link")
	ns.link = Fields.create("abc")
	State.closeLink(ns, false)
	assert(ns.mode == "board" and ns.link.text == "abc")
	State.openLink(ns)
	State.select(ns, "acme/web#301")
	assert(ns.mode == "board")
	State.openLink(ns)
	State.closeLink(ns, true)
	assert(ns.mode == "board" and ns.link.text == "")

	-- Show on the board: the PR's tab, with a search or filter that hides it cleared.
	local ss = fresh({ tab = "mine" })
	State.setSearch(ss, "zzz")
	State.toggleRepository(ss, "acme/web")
	assert(State.show(ss, "acme/web#301") and ss.tab == "review" and ss.selected == "acme/web#301" and ss.search.text == "" and ss.repositories == nil)
	assert(not State.show(ss, "acme/none#1"))
	local idle = State.show(fresh(), "acme/api#122")
	assert(idle)

	-- The added set: the cap is 50, and a fetched PR's own spelling of the repo wins.
	local set: { [string]: Model.PRRef }? = {}
	for n = 1, 50 do set = State.withAdded(set :: any, { repo = "o/r", number = n }) end
	assert(set ~= nil and set["o/r#50"] ~= nil)
	local over, why = State.withAdded(set :: any, { repo = "o/r", number = 51 })
	assert(over == nil and why == "50 pull requests are added already. Remove one first.")
	local again = State.withAdded(set :: any, { repo = "o/r", number = 7 })
	assert(again == set, "adding one already there changes nothing")
	local canon, changed = State.canonicalAdded({ ["ACME/web#303"] = { repo = "ACME/web", number = 303 }, ["x/y#1"] = { repo = "x/y", number = 1 } }, copy(Cases.prs))
	assert(changed and canon["acme/web#303"] ~= nil and canon["acme/web#303"].repo == "acme/web" and canon["ACME/web#303"] == nil and canon["x/y#1"] ~= nil)
	local _, same = State.canonicalAdded({ ["acme/web#303"] = { repo = "acme/web", number = 303 } }, copy(Cases.prs))
	assert(not same)

	-- Remove (X): an added PR with no other reason to be on the board leaves it; one that is also requested stays.
	local rs2 = fresh({ tab = "review" })
	assert(byKey(rs2, "acme/web#303").addedByMe and not byKey(rs2, "acme/web#303").reviews.requestedMe)
	State.unadd(rs2, "acme/web#303")
	assert(State.card(rs2, "acme/web#303") == nil)
	local both2 = fresh({ tab = "review" })
	byKey(both2, "acme/web#303").reviews.requestedMe = true
	State.unadd(both2, "acme/web#303")
	assert(State.card(both2, "acme/web#303") ~= nil and not byKey(both2, "acme/web#303").addedByMe)

	-- Opening a card: a checkout, PR Guide's own copy, or nothing (a toast with the reason, no open).
	local plan = State.openPlan("acme/api", 412, false, "/Users/me/code/api", nil, "/Users/me/code/hub")
	assert(plan.kind == "open" and plan.url == "https://github.com/acme/api/pull/412#prguide-open=%2FUsers%2Fme%2Fcode%2Fapi")
	plan = State.openPlan("acme/api", 412, true, "/Users/me/code/api", nil, "/Users/me/code/hub")
	assert(plan.kind == "open" and plan.url == "https://github.com/acme/api/pull/412#prguide-open=%2FUsers%2Fme%2Fcode%2Fapi&generate=true")
	plan = State.openPlan("acme/api", 412, false, nil, nil, "/Users/me/code/hub")
	assert(plan.kind == "open" and plan.url == "https://github.com/acme/api/pull/412#prguide-open=%2FUsers%2Fme%2Fcode%2Fhub&search=true")
	plan = State.openPlan("acme/api", 412, true, nil, nil, "/Users/me/code/hub")
	assert(plan.kind == "open" and plan.url == "https://github.com/acme/api/pull/412#prguide-open=%2FUsers%2Fme%2Fcode%2Fhub&generate=true&search=true")
	plan = State.openPlan("acme/api", 412, false, nil, "PR Guide only downloads repos on github.com.", "/x")
	assert(plan.kind == "refuse" and plan.text == "Couldn't open #412 of acme/api" and plan.sub == "PR Guide only downloads repos on github.com.")
	plan = State.openPlan("acme/api", 412, false, nil, nil, "")
	assert(plan.kind == "refuse" and plan.sub == "No folder to look for a checkout in.")

	-- Next up: opening never moves the selection; `.` visits the fixture's keys in order across both tabs.
	local walk = fresh()
	assert(walk.selected == nil and not walk.walking)
	assert(walk.board.nextUp and walk.board.nextUp.index == 1 and walk.board.nextUp.total == #Cases.nextUp)
	assert(walk.board.nextUp.item.key == Cases.nextUp[1])
	local visited, tabs = {}, {}
	for _ = 1, #Cases.nextUp do
		assert(State.walk(walk))
		table.insert(visited, walk.selected :: string)
		table.insert(tabs, walk.tab)
		assert(walk.walking and State.selectedCard(walk) ~= nil)
		local up = walk.board.nextUp :: Model.NextUp
		assert(up.index == (#visited % #Cases.nextUp) + 1, "banner position")
	end
	assert(join(visited) == join(Cases.nextUp), join(visited))
	assert(table.find(tabs, "mine") and table.find(tabs, "review"))
	assert(State.walk(walk) and walk.selected == Cases.nextUp[1], "wraps")
	State.move(walk, "down")
	assert(not walk.walking and walk.board.nextUp and walk.board.nextUp.index == 1, "moving ends the walk")

	-- Walking reveals an item the search hides, and the banner builds the item's card.
	local hidden = fresh()
	State.setSearch(hidden, "zzz-no-match")
	assert(State.walk(hidden) and hidden.search.text == "" and hidden.selected == Cases.nextUp[1])
	local nextCard = State.nextCard(hidden)
	assert(nextCard and nextCard.pr.key == Cases.nextUp[2] and #nextCard.chips > 0)

	-- Nothing needs the viewer: no banner and `.` does nothing.
	local quiet = fresh()
	quiet.prs = {}
	State.project(quiet)
	assert(quiet.board.nextUp == nil and State.nextCard(quiet) == nil and not State.walk(quiet))
end
