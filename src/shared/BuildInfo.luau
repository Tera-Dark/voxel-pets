--!strict
-- Build identity shown in game (loading screen + bottom-right corner) so any screenshot tells
-- exactly which build is running (a stale .rbxl reopened from an old Studio session looks
-- identical otherwise). VERSION is bumped by hand per delivery; BUILD is stamped by
-- scripts/build.sh with the git short hash + UTC date. "dev" = unstamped build (e.g. rojo serve).
return {
	VERSION = "0.4.0",
	BUILD = "dev",
}
