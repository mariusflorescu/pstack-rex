-- pstack-rex watcher: turns what happens in worker panes into wake-ups for the main agent.
-- `subagent` starts one per Rex session as `rex do -s SESSION watch.lua --args {cli, state, settle}`
-- and it stops itself once the session has no open workers. Panes `subagent` didn't open are ignored.

local cli = rex.args.cli
local by_block = rex.args.state .. "/by-block/"
local settle = tonumber(rex.args.settle or 45)
local session = rex.session_id

local function key(block) return (block or ""):gsub("^[^:]*:", "") end

-- subagent keeps by-block/<id> for every open worker and by-block/<id>.main for every main pane
local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end
local function registered(block) return block ~= nil and exists(by_block .. key(block)) end
local function is_main(block) return block ~= nil and exists(by_block .. key(block) .. ".main") end

local function run(argv)
  local r, err = rex.exec(argv, { timeout = 90 })
  if not r then
    print("subagent failed to start: " .. tostring(err))
    return ""
  end
  if not r.ok then print(argv[2] .. " exited " .. tostring(r.code) .. ": " .. r.stdout .. r.stderr) end
  return r.stdout or ""
end

-- Events that land within 2s reach the main agent as one line
local pending = {}
local function deliver_soon(main)
  if pending[main] then pending[main]:cancel() end
  pending[main] = rex.after(2, function()
    pending[main] = nil
    run({ cli, "_deliver", main })
  end)
end

local function react(out, block)
  for main in out:gmatch("notify (%S+)") do deliver_soon(main) end
  local turn = out:match("settle (%S+)")
  if turn then
    rex.after(settle, function() react(run({ cli, "_settle", block, turn }), block) end)
  end
end

local function event(block, ...)
  local argv = { cli, "_event", block }
  -- Not ipairs: it stops at the first nil, and kind/msg are nil for most states
  for i = 1, select("#", ...) do argv[#argv + 1] = tostring((select(i, ...)) or "") end
  react(run(argv), block)
end

-- A wake-up for a Claude main on a dialog waits until it leaves the dialog
local main_state = {}

rex.on("terminal.program_status_changed", function(ctx, ev)
  -- Only the root record: that's the agent's own state
  if ev.id and ev.id ~= "" then return end
  local r = ev.record or {}
  if registered(ctx.block_id) then
    event(ctx.block_id, "status", r.state, r.kind, r.msg)
  elseif is_main(ctx.block_id) then
    if main_state[ctx.block_id] == "blocked" and r.state ~= "blocked" then deliver_soon(ctx.block_id) end
    main_state[ctx.block_id] = r.state
  end
end)

rex.on("terminal.child_exited", function(ctx, ev)
  if registered(ctx.block_id) then event(ctx.block_id, "exited", ev.exit_code) end
end)

rex.on("block_closed", function(ctx, ev)
  if registered(ev.block_id) then event(ev.block_id, "closed") end
end)

rex.every(30, function()
  if run({ cli, "_watcher_check", session }):match("stop") then rex.stop(0) end
end)
