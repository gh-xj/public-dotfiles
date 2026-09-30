-- Exercise the plugin's public entry points against real disposable files.
-- Yazi UI adapters are stubbed; filesystem operations and JSON are not.
local root, fixture = assert(arg[1]), assert(arg[2])
local json = dofile(root .. "/.config/yazi/plugins/projects.yazi/json.lua")
assert(json.decode("[null]")[1] == json.null)
assert(json.encode(json.decode("[null]")) == "[null]")
package.loaded[".json"] = json
local active, choice, name
ya = {
    sync = function(fn)
        local state = active
        return function(...) return fn(state, ...) end
    end,
    notify = function(message) active.notifications[#active.notifications + 1] = message end,
    emit = function(action) active.actions[#active.actions + 1] = action end,
    which = function() return choice end,
    input = function() return name or "Fixture", 1 end,
    quote = function(value) return "'" .. value:gsub("'", "'\\''") .. "'" end,
    time = function() return os.time() end,
}
ps = {
    pub_to = function(_, event) active.events[#active.events + 1] = event end,
    sub = function() end,
    sub_remote = function() end,
}
Url = function(path) return { parent = path:match("^(.*)/[^/]+$") } end
cx = { tabs = { idx = 1, { current = { cwd = fixture } } } }

local function read(path)
    local f = assert(io.open(path, "r"))
    local value = assert(f:read("*a"))
    assert(f:close())
    return value
end

local function write(path, data)
    local f = assert(io.open(path, "w"))
    assert(f:write(data))
    assert(f:close())
end

local function instance(path)
    local state = { notifications = {}, events = {}, actions = {} }
    active = state
    local plugin = dofile(root .. "/.config/yazi/plugins/projects.yazi/main.lua")
    plugin.setup(state, { save = { method = "lua", lua_save_path = path } })
    return { plugin = plugin, state = state, path = path }
end

local function invoke(test, action, slot, description)
    active, choice, name = test.state, slot or 1, description
    test.plugin.entry(nil, { args = { action } })
end

local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not equal(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function unchanged_after_failure(test, action)
    local contents, projects = read(test.path), test.state.projects
    local count = #test.state.events
    local original = os.rename
    os.rename = function() return nil, "injected rename failure" end
    invoke(test, action)
    os.rename = original
    assert(read(test.path) == contents, action .. " changed the original on failure")
    assert(equal(test.state.projects, projects), action .. " changed cached projects on failure")
    assert(#test.state.events == count, action .. " broadcast a success event on failure")
    assert(test.state.notifications[#test.state.notifications].level == "error")
end

-- A first save creates missing parents, including paths with quotes and spaces.
local path = fixture .. "/quote's parent/missing/projects.json"
local first = instance(path)
invoke(first, "save", 37, "Alpha")
assert(json.decode(read(path)).list[1].desc == "Alpha")
assert(first.state.events[1] == "project-saved")
assert(first.state.notifications[#first.state.notifications].content == "Project saved to a")

-- Restart restores the original format. A second instance refreshes before
-- saving so sequential writes from two already-open sessions preserve slots.
local second = instance(path)
assert(second.state.projects.list[1].desc == "Alpha")
invoke(second, "save", 38, "Beta")
invoke(first, "save", 39, "Gamma")
assert(#json.decode(read(path)).list == 3)

-- Rename failures leave the saved list, last, events and tab actions intact.
for _, action in ipairs({ "save", "delete", "delete_all", "load", "load_last" }) do
    local actions = #first.state.actions
    unchanged_after_failure(first, action)
    assert(#first.state.actions == actions, action .. " changed tabs after a failed save")
end

-- Write and close errors also keep the destination and cached state intact.
for _, operation in ipairs({ "write", "close" }) do
    local contents, events = read(path), #first.state.events
    local original_open = io.open
    io.open = function(file, mode)
        local f, err, code = original_open(file, mode)
        if mode ~= "w" or not f then return f, err, code end
        return {
            write = function(_, data)
                if operation == "write" then return nil, "injected write failure" end
                return f:write(data)
            end,
            close = function()
                local ok, why = f:close()
                if operation == "close" then return nil, "injected close failure" end
                return ok, why
            end,
        }
    end
    invoke(first, "save", 40)
    io.open = original_open
    assert(read(path) == contents, operation .. " failure changed the original")
    assert(#first.state.events == events)
    assert(#first.state.projects.list == 3)
    assert(first.state.notifications[#first.state.notifications].level == "error")
end

-- Invalid JSON and valid JSON with an unusable shape are preserved, even
-- when save/delete-all is retried. Repairing the file permits the next action.
local valid_slot = first.state.projects.list[1]
local bad_tabs = { on = "a", desc = "Broken", project = {
    active_idx = 1, tabs = { { idx = 1, cwd = fixture }, json.null },
} }
for _, contents in ipairs({
    "{broken", "{}", '{"list":[{"on":"a"}]}', '{"list":null}',
    json.encode({ list = { valid_slot, json.null } }),
    json.encode({ list = { bad_tabs } }),
}) do
    write(path, contents)
    local broken = instance(path)
    invoke(broken, "save", 37)
    invoke(broken, "delete_all")
    assert(read(path) == contents)
    assert(#broken.state.events == 0)
    assert(broken.state.notifications[#broken.state.notifications].level == "error")
    write(path, '{"list":[]}')
    invoke(broken, "save", 37, "Repaired")
    assert(json.decode(read(path)).list[1].desc == "Repaired")
end

write(path, '{"list":[],"last":null}')
local null_last = instance(path)
assert(null_last.state.projects.last == nil)
invoke(null_last, "save", 37, "Null last is supported")
assert(json.decode(read(path)).list[1].desc == "Null last is supported")

-- A file used as the parent is an error, not an empty list/new installation.
local blocker = fixture .. "/parent-is-file"
write(blocker, "preserve me")
local blocked = instance(blocker .. "/projects.json")
invoke(blocked, "save", 37)
assert(read(blocker) == "preserve me")
assert(#blocked.state.events == 0)
assert(blocked.state.notifications[#blocked.state.notifications].level == "error")

-- Successful deletion persists and broadcasts only after the write completes.
local clean = instance(path)
invoke(clean, "delete")
assert(#json.decode(read(path)).list == 0)
assert(clean.state.events[1] == "project-deleted")
invoke(clean, "delete_all")
assert(clean.state.events[2] == "project-deleted-all")
io.stdout:write("Projects persistence: save/restart/refresh, errors, recovery and deletion passed\n")
