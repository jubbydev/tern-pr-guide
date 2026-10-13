--!strict
-- Runs every test module. A failed assert names its module and exits non-zero.
-- Tests require pure modules. summary_test, tandem_test, fold_test, rerun_test and branch_test also load block (summary_test and
-- tandem_test fetch too), and prepare_test loads hub/prepare with fetch, prdata and agent-host, with the Host table's fields stubbed and every process effect a recorded callback;
-- platform_test swaps only Host's runtime and getenv. No other test touches a host module.

local modules: { { name: string, run: () -> () } } = {
	{ name = "model_test", run = require("./model_test") },
	{ name = "github_test", run = require("./github_test") },
	{ name = "state_test", run = require("./state_test") },
	{ name = "filter_test", run = require("./filter_test") },
	{ name = "sync_test", run = require("./sync_test") },
	{ name = "links_test", run = require("./links_test") },
	{ name = "merge_test", run = require("./merge_test") },
	{ name = "fixes_test", run = require("./fixes_test") },
	{ name = "selection_test", run = require("./selection_test") },
	{ name = "flake_test", run = require("./flake_test") },
	{ name = "rereview_test", run = require("./rereview_test") },
	{ name = "agent_fix_test", run = require("./agent_fix_test") },
	{ name = "agent_state_test", run = require("./agent_state_test") },
	{ name = "review_fix_test", run = require("./review_fix_test") },
	{ name = "summary_test", run = require("./summary_test") },
	{ name = "tandem_test", run = require("./tandem_test") },
	{ name = "moves_test", run = require("./moves_test") },
	{ name = "diff_test", run = require("./diff_test") },
	{ name = "groups_test", run = require("./groups_test") },
	{ name = "flow_test", run = require("./flow_test") },
	{ name = "fold_test", run = require("./fold_test") },
	{ name = "ci_log_test", run = require("./ci_log_test") },
	{ name = "rerun_test", run = require("./rerun_test") },
	{ name = "checks_test", run = require("./checks_test") },
	{ name = "branch_test", run = require("./branch_test") },
	{ name = "draft_test", run = require("./draft_test") },
	{ name = "agent_test", run = require("./agent_test") },
	{ name = "agent_diff_test", run = require("./agent_diff_test") },
	{ name = "passes_test", run = require("./passes_test") },
	{ name = "model_menu_test", run = require("./model_menu_test") },
	{ name = "hub_settings_test", run = require("./hub_settings_test") },
	{ name = "prepare_test", run = require("./prepare_test") },
	{ name = "pages_test", run = require("./pages_test") },
	{ name = "platform_test", run = require("./platform_test") },
}

local failed = 0
for _, module in modules do
	local ok, err = pcall(module.run)
	if ok then
		print("ok   " .. module.name)
	else
		failed += 1
		print("FAIL " .. module.name .. ": " .. tostring(err))
	end
end
if failed > 0 then error(failed .. " test module(s) failed", 0) end
print("all " .. #modules .. " test module(s) passed")
