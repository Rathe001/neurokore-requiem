extends Node

# Build metadata. VERSION + CHANNEL are bumped manually before each
# playtest export so bug reports map back to a specific build. Stamp
# them into log lines, save data, and any in-game version display.

const VERSION := "0.1.2"
const BUILD_DATE := "2026-05-06"
const CHANNEL := "playtest"
const BUG_REPORT_URL := "https://github.com/Rathe001/neurokore-requiem/issues/new"

# True in the editor AND in debug exports. Release exports (which is what
# we ship to the playtest) get false, so F-key debug shortcuts and the
# debug panel stay hidden from real players. Debug exports are
# dev/QA-only — that's exactly the case we want the panel available for.
func dev_tools_enabled() -> bool:
	return OS.has_feature("debug")

func display_string() -> String:
	return "v%s · %s · %s" % [VERSION, CHANNEL, BUILD_DATE]
