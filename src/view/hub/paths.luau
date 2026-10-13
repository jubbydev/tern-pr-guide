--!strict
-- Node ids of the hub page that the block scrolls to and menus anchor to. They follow the keys in board.luau.
local State = require("../../hub/state")
local Text = require("../../text")

local M = {}

M.ROOT = "main.hub"
M.searchField = M.ROOT .. ".header.top.search.field"
-- The board's scrolling body, under the header.
M.body = M.ROOT .. ".body"
M.titleLabel = M.ROOT .. ".header.top.title"
M.settingsButton = M.ROOT .. ".header.top.fresh.settings"
-- Settings' model search field, in the layer over the board.
M.settingsField = "layer.menu.body.box.field"
M.repositoriesButton = M.ROOT .. ".header.tabs.ctls.repos"
M.sortButton = M.ROOT .. ".header.tabs.ctls.sort"
-- The add-by-link field, at the top of the To review column.
M.linkField = M.ROOT .. ".body.board.col_to_review.add.row.field"

-- The key of a card's node, unique on the board.
function M.cardKey(prKey: string): string
	return "c_" .. Text.keyOf(prKey)
end

function M.columnKey(column: string): string
	return "col_" .. column
end

-- The key of a fold's node under the board: "fold" for Inactive, else its name ("team", "approved", "recent", "merged").
function M.foldKey(column: string): string
	return if column == "inactive" then "fold" else column
end

-- A fold's header, which the block scrolls to the top when the fold opens.
function M.foldHead(column: string): string
	return M.ROOT .. ".body." .. M.foldKey(column) .. ".head"
end

-- The card's node: in its column, or in its fold.
function M.card(card: State.Card): string
	if State.isFold(card.column) then
		return M.ROOT .. ".body." .. M.foldKey(card.column) .. ".rows." .. M.cardKey(card.pr.key)
	end
	return M.ROOT .. ".body.board." .. M.columnKey(card.column) .. "." .. M.cardKey(card.pr.key)
end

-- The selection bar: at the top of Ready to merge, or of the Inactive rows.
function M.selection(group: string): string
	if group == "inactive" then return M.ROOT .. ".body.fold.rows.selection" end
	return M.ROOT .. ".body.board." .. M.columnKey("ready") .. ".selection"
end

-- The key of a row fold's row node (`key` is State.recentKey).
function M.recentKey(key: string): string
	return "rc_" .. Text.keyOf(key)
end

-- A row fold's row node, in the fold `name` (State.ROW_FOLD).
function M.recentRow(name: string, key: string): string
	return M.ROOT .. ".body." .. name .. ".rows." .. M.recentKey(key)
end

-- The fixes page and the reply field inside the thread card on show. They follow the keys in fixes.luau.
M.FIXES = "main.fixes"
M.replyField = M.FIXES .. ".cols.code.ex.body.composer.body.field"

-- The ▾ beside a selected card's split button, which the card's menu anchors to.
function M.moreButton(card: State.Card): string
	return M.card(card) .. ".body.meta.acts.sb.more"
end

return M
