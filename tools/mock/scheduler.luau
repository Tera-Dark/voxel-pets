--!nonstrict
-- ---------------------------------------------------------------- virtual-time scheduler
-- Optional (Mock.new(root, { scheduler = true })): task.spawn/defer/delay/wait run as coroutines
-- against a virtual clock, so timeouts, watchdogs and yields behave like Roblox. M.advance(s)
-- runs everything due within the next s virtual seconds. The default (synchronous) mode keeps
-- the original semantics: spawn runs inline, delay runs immediately, task.wait errors.
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(M)
	return setmetatable(
		{ M = M, queue = {}, seq = 0, managed = setmetatable({}, { __mode = "k" }) },
		Scheduler
	)
end

function Scheduler:resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		if self.M.onTaskError then
			self.M.onTaskError(err, co)
		else
			warn("[mock task] " .. tostring(err) .. "\n" .. debug.traceback(co))
		end
	end
end

function Scheduler:spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	self.managed[co] = true
	self:resume(co, ...)
	return co
end

function Scheduler:push(at, co, args)
	self.seq += 1
	table.insert(self.queue, { at = at, seq = self.seq, co = co, args = args })
end

function Scheduler:delay(t, fn, ...)
	local co = coroutine.create(fn)
	self.managed[co] = true
	self:push(self.M.clock + (t or 0), co, table.pack(...))
	return co
end

function Scheduler:wait(t)
	local co = coroutine.running()
	if not self.managed[co] then
		error("mock: task.wait outside a scheduler task (wrap the caller in M.spawn)")
	end
	local start = self.M.clock
	self:push(start + math.max(t or 0, 0), co, nil)
	coroutine.yield()
	return self.M.clock - start
end

function Scheduler:runUntil(target)
	local steps = 0
	while true do
		table.sort(self.queue, function(a, b)
			if a.at ~= b.at then
				return a.at < b.at
			end
			return a.seq < b.seq
		end)
		local item = self.queue[1]
		if not item or item.at > target then
			break
		end
		table.remove(self.queue, 1)
		self.M.clock = math.max(self.M.clock, item.at)
		if coroutine.status(item.co) == "suspended" then
			if item.args then
				self:resume(item.co, table.unpack(item.args, 1, item.args.n))
			else
				self:resume(item.co)
			end
		end
		steps += 1
		assert(steps < 500000, "mock scheduler: runaway task loop")
	end
	self.M.clock = math.max(self.M.clock, target)
end

return Scheduler
