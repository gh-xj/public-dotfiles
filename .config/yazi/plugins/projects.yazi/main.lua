local SUPPORTED_KEYS_MAP = {
    ["0"] = 1,
    ["1"] = 2,
    ["2"] = 3,
    ["3"] = 4,
    ["4"] = 5,
    ["5"] = 6,
    ["6"] = 7,
    ["7"] = 8,
    ["8"] = 9,
    ["9"] = 10,
    ["A"] = 11,
    ["B"] = 12,
    ["C"] = 13,
    ["D"] = 14,
    ["E"] = 15,
    ["F"] = 16,
    ["G"] = 17,
    ["H"] = 18,
    ["I"] = 19,
    ["J"] = 20,
    ["K"] = 21,
    ["L"] = 22,
    ["M"] = 23,
    ["N"] = 24,
    ["O"] = 25,
    ["P"] = 26,
    ["Q"] = 27,
    ["R"] = 28,
    ["S"] = 29,
    ["T"] = 30,
    ["U"] = 31,
    ["V"] = 32,
    ["W"] = 33,
    ["X"] = 34,
    ["Y"] = 35,
    ["Z"] = 36,
    ["a"] = 37,
    ["b"] = 38,
    ["c"] = 39,
    ["d"] = 40,
    ["e"] = 41,
    ["f"] = 42,
    ["g"] = 43,
    ["h"] = 44,
    ["i"] = 45,
    ["j"] = 46,
    ["k"] = 47,
    ["l"] = 48,
    ["m"] = 49,
    ["n"] = 50,
    ["o"] = 51,
    ["p"] = 52,
    ["q"] = 53,
    ["r"] = 54,
    ["s"] = 55,
    ["t"] = 56,
    ["u"] = 57,
    ["v"] = 58,
    ["w"] = 59,
    ["x"] = 60,
    ["y"] = 61,
    ["z"] = 62,
}

local SUPPORTED_KEYS = {
    { on = "0" },
    { on = "1" },
    { on = "2" },
    { on = "3" },
    { on = "4" },
    { on = "5" },
    { on = "6" },
    { on = "7" },
    { on = "8" },
    { on = "9" },
    { on = "A" },
    { on = "B" },
    { on = "C" },
    { on = "D" },
    { on = "E" },
    { on = "F" },
    { on = "G" },
    { on = "H" },
    { on = "I" },
    { on = "J" },
    { on = "K" },
    { on = "L" },
    { on = "M" },
    { on = "N" },
    { on = "O" },
    { on = "P" },
    { on = "Q" },
    { on = "R" },
    { on = "S" },
    { on = "T" },
    { on = "U" },
    { on = "V" },
    { on = "W" },
    { on = "X" },
    { on = "Y" },
    { on = "Z" },
    { on = "a" },
    { on = "b" },
    { on = "c" },
    { on = "d" },
    { on = "e" },
    { on = "f" },
    { on = "g" },
    { on = "h" },
    { on = "i" },
    { on = "j" },
    { on = "k" },
    { on = "l" },
    { on = "m" },
    { on = "n" },
    { on = "o" },
    { on = "p" },
    { on = "q" },
    { on = "r" },
    { on = "s" },
    { on = "t" },
    { on = "u" },
    { on = "v" },
    { on = "w" },
    { on = "x" },
    { on = "y" },
    { on = "z" },
}

local _notify = ya.sync(function(state, message)
    ya.notify({
        title = state.notify.title,
        content = message,
        timeout = state.notify.timeout,
        level = state.notify.level,
    })
end)

local _get_default_projects = ya.sync(function(state)
    return {
        list = {},
        last = nil,
    }
end)

-- The lua backend is a local Unix/macOS fork. Always read the latest file
-- before an action, and never turn unreadable or malformed data into an empty
-- project list that a later save could overwrite.
local function valid_project(project)
    if type(project) ~= "table" or type(project.tabs) ~= "table" then
        return false
    end
    local count = #project.tabs
    local active = project.active_idx
    if count == 0 or type(active) ~= "number" or active % 1 ~= 0 or active < 1 or active > count then
        return false
    end
    local indexes, seen = {}, 0
    for key, tab in pairs(project.tabs) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
            return false
        end
        if type(tab) ~= "table" or type(tab.cwd) ~= "string" or tab.cwd == "" then
            return false
        end
        local idx = tonumber(tab.idx)
        if not idx or idx % 1 ~= 0 or idx < 1 or idx > count or indexes[idx] then
            return false
        end
        indexes[idx] = true
        seen = seen + 1
    end
    return seen == count
end

local function valid_projects(projects)
    if type(projects) ~= "table" or type(projects.list) ~= "table" then
        return false
    end
    local slots, seen = {}, 0
    for key, item in pairs(projects.list) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #projects.list then
            return false
        end
        if type(item) ~= "table" or not SUPPORTED_KEYS_MAP[item.on] or slots[item.on]
            or type(item.desc) ~= "string" or not valid_project(item.project) then
            return false
        end
        slots[item.on] = true
        seen = seen + 1
    end
    return seen == #projects.list and (projects.last == nil or valid_project(projects.last))
end

local function persistence_error(state, message)
    ya.notify({
        title = state.notify.title,
        content = "Projects file unchanged: " .. state.save.lua_save_path .. "\n"
            .. tostring(message) .. "\nCheck permissions, or back up and repair the file, then retry.",
        timeout = 10,
        level = "error",
    })
end

local function read_projects(state)
    local f, err, code = io.open(state.save.lua_save_path, "r")
    if not f then
        if code == 2 then -- ENOENT: a new installation has no saved file yet.
            return { list = {} }
        end
        return nil, err
    end
    local data, read_err = f:read("*a")
    local closed, close_err = f:close()
    if not data or not closed then
        return nil, read_err or close_err
    end
    local ok, projects = pcall(state.json.decode, data)
    if ok and type(projects) == "table" then
        -- Historically the decoder treated last:null as an absent last.
        if projects.last == state.json.null then
            projects.last = nil
        end
        if projects.list == state.json.null then
            return nil, "Invalid JSON or project structure"
        end
    end
    if not ok or not valid_projects(projects) then
        return nil, "Invalid JSON or project structure"
    end
    return projects
end

local _get_projects = ya.sync(function(state)
    local projects = state.projects or _get_default_projects()
    if state.save.method == "lua" then
        local err
        projects, err = read_projects(state)
        if not projects then
            persistence_error(state, err)
            return nil
        end
        state.projects = projects
    end
    -- Mutations remain detached from cached state until persistence succeeds.
    local copy = { list = {}, last = projects.last }
    for idx, item in ipairs(projects.list) do
        copy.list[idx] = item
    end
    return copy
end)

local function get_real_idx(projects, slot)
    for idx, item in ipairs(projects.list) do
        if item.on == slot then
            return idx
        end
    end
end

local _get_current_project = ya.sync(function(state)
    local tabs = cx.tabs

    -- TODO: add more tab properties
    local project = {
        active_idx = tonumber(tabs.idx),
        tabs = {},
    }

    for index, tab in ipairs(tabs) do
        project.tabs[#project.tabs + 1] = {
            idx = index,
            cwd = tostring(tab.current.cwd):gsub("\\", "/"),
        }
    end

    return project
end)

local _save_projects = ya.sync(function(state, projects)
    if state.save.method == "yazi" then
        ps.pub_to(0, state.save.yazi_load_event, projects)
    elseif state.save.method == "lua" then
        local encoded, data = pcall(state.json.encode, projects)
        if not encoded then
            persistence_error(state, "Could not encode projects")
            return false
        end

        local path = state.save.lua_save_path
        local parent = Url(path).parent
        -- fs.create is async-only; this plugin's small persistence operation
        -- runs in sync callbacks. Quote the path and check mkdir's exit status.
        local created = os.execute("mkdir -p -- " .. ya.quote(tostring(parent or ".")))
        if created ~= true and created ~= 0 then
            persistence_error(state, "Could not create the parent directory")
            return false
        end

        -- Adjacent temporary files keep rename on the same filesystem. A
        -- timestamp plus random suffix separates concurrent Yazi instances.
        local temporary = path .. ".tmp-" .. tostring(ya.time()) .. "-" .. tostring(math.random(0, 2147483647))
        local f, err = io.open(temporary, "w")
        if not f then
            persistence_error(state, err)
            return false
        end
        local written, write_err = f:write(data)
        local closed, close_err = f:close()
        if not written or not closed then
            os.remove(temporary)
            persistence_error(state, write_err or close_err)
            return false
        end
        local renamed, rename_err = os.rename(temporary, path)
        if not renamed then
            os.remove(temporary)
            persistence_error(state, rename_err)
            return false
        end
    else
        persistence_error(state, "Unknown save method")
        return false
    end

    state.projects = projects
    return true
end)

local save_project = ya.sync(function(state, idx, desc)
    local projects = _get_projects()
    if not projects then
        return
    end

    local real_idx = get_real_idx(projects, SUPPORTED_KEYS[idx].on)
    if not real_idx then
        real_idx = #projects.list + 1
    end

    local project = _get_current_project()
    projects.list[real_idx] = {
        on = SUPPORTED_KEYS[idx].on,
        desc = desc,
        project = project,
    }

    if state.last.update_after_save then
        projects.last = project
    end

    if not _save_projects(projects) then
        return
    end

    if state.event.save.enable then
        ps.pub_to(0, state.event.save.name, project)
    end

    if state.notify.enable then
        local message = string.format("Project saved to %s", state.projects.list[real_idx].on)
        _notify(message)
    end
end)

local load_project = ya.sync(function(state, project, desc)
    if state.last.update_after_load then
        local projects = _get_projects()
        if not projects then
            return
        end
        projects.last = project
        if not _save_projects(projects) then
            return
        end
    end

    -- TODO: add more tab properties to restore

    -- when cx is nil, it is called in setup
    if cx then
        for _ = 1, #cx.tabs - 1 do
            ya.emit("tab_close", { 0 })
        end
    end

    local sorted_tabs = {}
    for _, tab in pairs(project.tabs) do
        sorted_tabs[tonumber(tab.idx)] = tab
    end
    for _, tab in pairs(sorted_tabs) do
        ya.emit("tab_create", { tab.cwd })
    end

    ya.emit("tab_close", { 0 })
    ya.emit("tab_switch", { project.active_idx - 1 })

    if state.event.load.enable then
        ps.pub_to(0, state.event.load.name, project)
    end

    if state.notify.enable then
        local message
        if desc then
            message = string.format([["%s" loaded]], desc)
        else
            message = string.format([[Last project loaded]], desc)
        end
        _notify(message)
    end
end)

local _load_projects = ya.sync(function(state)
    if state.save.method == "yazi" then
        ps.sub_remote(state.save.yazi_load_event, function(body)
            state.projects = body
        end)
    end

    local projects = _get_projects()
    if projects and state.last.load_after_start and projects.last then
        load_project(projects.last)
    end
end)

local delete_all_projects = ya.sync(function(state)
    -- Even delete-all must refuse to overwrite an unreadable existing file.
    if not _get_projects() or not _save_projects(_get_default_projects()) then
        return
    end

    local msg = "All projects deleted"

    if state.event.delete_all.enable then
        ps.pub_to(0, state.event.delete_all.name, msg)
    end

    if state.notify.enable then
        _notify(msg)
    end
end)

local delete_project = ya.sync(function(state, slot)
    local projects = _get_projects()
    if not projects then
        return
    end
    local idx = get_real_idx(projects, slot)
    if not idx then
        return
    end

    local message = string.format([["%s" deleted]], tostring(projects.list[idx].desc))

    local deleted_project = projects.list[idx]
    table.remove(projects.list, idx)
    if not _save_projects(projects) then
        return
    end

    if state.event.delete.enable then
        ps.pub_to(0, state.event.delete.name, deleted_project)
    end

    if state.notify.enable then
        _notify(message)
    end
end)

local merge_project = ya.sync(function(state, opt)
    local project = _get_current_project()
    project.opt = opt or "all"
    ps.pub_to(0, state.merge.event, project)

    if state.event.merge.enable then
        ps.pub_to(0, state.event.merge.name, project)
    end

    if state.merge.quit_after_merge then
        ya.emit("quit", {})
    end
end)

local _merge_tab = ya.sync(function(state, tab)
    ya.emit("tab_create", { tab.cwd })
end)

local _merge_event = ya.sync(function(state)
    ps.sub_remote(state.merge.event, function(body)
        if body then
            local active_idx = tonumber(cx.tabs.idx)

            local opt = body.opt
            if opt == "all" then
                local sorted_tabs = {}
                for _, tab in pairs(body.tabs) do
                    sorted_tabs[tonumber(tab.idx)] = tab
                end

                for _, tab in ipairs(sorted_tabs) do
                    _merge_tab(tab)
                end

                if state.notify.enable then
                    local message = "A project is merged"
                    _notify(message)
                end
            elseif opt == "current" then
                local tab = body.tabs[tonumber(body.active_idx)]
                _merge_tab(tab)

                if state.notify.enable then
                    local message = "A tab is merged"
                    _notify(message)
                end
            end

            ya.emit("tab_switch", { active_idx - 1 })
        end
    end)
end)

local _find_project_index = ya.sync(function(state, list, search_term)
    if not search_term then
        return nil
    end

    for i, project in ipairs(list) do
        -- Match the project by the "on" key or by "desc"
        if project.on == search_term or project.desc == search_term then
            return i
        end
    end

    return nil
end)

local _load_config = ya.sync(function(state, opts)
    state.event = {
        save = {
            enable = true,
            name = "project-saved",
        },
        load = {
            enable = true,
            name = "project-loaded",
        },
        delete = {
            enable = true,
            name = "project-deleted",
        },
        delete_all = {
            enable = true,
            name = "project-deleted-all",
        },
        merge = {
            enable = true,
            name = "project-merged",
        },
    }
    if type(opts.event) == "table" then
        if type(opts.event.save) == "table" then
            if type(opts.event.save.enable) == "boolean" then
                state.event.save.enable = opts.event.save.enable
            end
            if type(opts.event.save.name) == "string" then
                state.event.save.name = opts.event.save.name
            end
        elseif type(opts.event.save) == "boolean" then
            state.event.save.enable = opts.event.save
        end
        if type(opts.event.load) == "table" then
            if type(opts.event.load.enable) == "boolean" then
                state.event.load.enable = opts.event.load.enable
            end
            if type(opts.event.load.name) == "string" then
                state.event.load.name = opts.event.load.name
            end
        elseif type(opts.event.load) == "boolean" then
            state.event.load.enable = opts.event.load
        end
        if type(opts.event.delete) == "table" then
            if type(opts.event.delete.enable) == "boolean" then
                state.event.delete.enable = opts.event.delete.enable
            end
            if type(opts.event.delete.name) == "string" then
                state.event.delete.name = opts.event.delete.name
            end
        elseif type(opts.event.delete) == "boolean" then
            state.event.delete.enable = opts.event.delete
        end
        if type(opts.event.delete_all) == "table" then
            if type(opts.event.delete_all.enable) == "boolean" then
                state.event.delete_all.enable = opts.event.delete_all.enable
            end
            if type(opts.event.delete_all.name) == "string" then
                state.event.delete_all.name = opts.event.delete_all.name
            end
        elseif type(opts.event.delete_all) == "boolean" then
            state.event.delete_all.enable = opts.event.delete_all
        end
        if type(opts.event.merge) == "table" then
            if type(opts.event.merge.enable) == "boolean" then
                state.event.merge.enable = opts.event.merge.enable
            end
            if type(opts.event.merge.name) == "string" then
                state.event.merge.name = opts.event.merge.name
            end
        elseif type(opts.event.merge) == "boolean" then
            state.event.merge.enable = opts.event.merge
        end
    end

    state.save = {
        method = "yazi",
        yazi_load_event = "@projects-load",
        lua_save_path = "",
    }
    if type(opts.save) == "table" then
        if type(opts.save.method) == "string" then
            state.save.method = opts.save.method
        end
        if type(opts.save.yazi_load_event) == "string" then
            state.save.yazi_load_event = opts.save.yazi_load_event
        end
        if type(opts.save.lua_save_path) == "string" then
            state.save.lua_save_path = opts.save.lua_save_path
        else
            local lua_save_path
            local appdata = os.getenv("APPDATA")
            if appdata then
                lua_save_path = appdata:gsub("\\", "/") .. "/yazi/state/projects.json"
            else
                lua_save_path = os.getenv("HOME") .. "/.local/state/yazi/projects.json"
            end

            state.save.lua_save_path = lua_save_path
        end
    end

    state.last = {
        update_after_save = true,
        update_after_load = true,
        update_before_quit = false,
        load_after_start = false,
    }
    if type(opts.last) == "table" then
        if type(opts.last.update_after_save) == "boolean" then
            state.last.update_after_save = opts.last.update_after_save
        end
        if type(opts.last.update_after_load) == "boolean" then
            state.last.update_after_load = opts.last.update_after_load
        end
        if type(opts.last.update_before_quit) == "boolean" then
            state.last.update_before_quit = opts.last.update_before_quit
        end
        if type(opts.last.load_after_start) == "boolean" then
            state.last.load_after_start = opts.last.load_after_start
        end
    end
    if state.last.update_before_quit then
        ps.sub("key-quit", function(body)
            local projects = _get_projects()
            if not projects then
                return true
            end
            local current_project = _get_current_project()
            projects.last = current_project
            if not _save_projects(projects) then
                return true
            end

            if state.event.save.enable then
                ps.pub_to(0, state.event.save.name, current_project)
            end

            ya.emit("quit", {})
            return true
        end)
    end

    state.merge = {
        event = "projects-merge",
        quit_after_merge = false,
    }
    if type(opts.merge) == "table" then
        if type(opts.merge.event) == "string" then
            state.merge.event = opts.merge.event
        end
        if type(opts.merge.quit_after_merge) == "boolean" then
            state.merge.quit_after_merge = opts.merge.quit_after_merge
        end
    end

    state.notify = {
        enable = true,
        title = "Projects",
        timeout = 3,
        level = "info",
    }
    if type(opts.notify) == "table" then
        if type(opts.notify.enable) == "boolean" then
            state.notify.enable = opts.notify.enable
        end
        if type(opts.notify.title) == "string" then
            state.notify.title = opts.notify.title
        end
        if type(opts.notify.timeout) == "number" then
            state.notify.timeout = opts.notify.timeout
        end
        if type(opts.notify.level) == "string" then
            state.notify.level = opts.notify.level
        end
    end
end)

return {
    setup = function(state, opts)
        state.json = require(".json")
        _load_config(opts)
        _load_projects()
        _merge_event()
    end,
    entry = function(_, job)
        local action = job.args[1]
        if not action then
            return
        end

        if action == "delete_all" then
            delete_all_projects()
            return
        end

        if action == "merge" then
            local opt = job.args[2]
            merge_project(opt)
            return
        end

        local projects = _get_projects()
        if not projects then
            return
        end

        if action == "load_last" then
            local last_project = projects.last
            if last_project then
                load_project(last_project)
            end
            return
        end

        local list = projects.list

        if action == "save" then
            for _, candidate in ipairs(SUPPORTED_KEYS) do
                candidate.desc = nil
            end
            -- load the desc of saved projects
            for _, value in pairs(list) do
                local idx = SUPPORTED_KEYS_MAP[value.on]
                if idx then
                    SUPPORTED_KEYS[idx].desc = value.desc
                end
            end

            local idx = ya.which({ cands = SUPPORTED_KEYS, silent = false })
            if not idx then
                return
            end

            -- if target is not empty, use the saved desc as default desc
            local default_desc = SUPPORTED_KEYS[idx].desc or string.format("Project %s", SUPPORTED_KEYS[idx].on)
            local value, event = ya.input({
                pos = { "center", w = 40 },
                title = "Project name:",
                value = default_desc,
            })
            if event ~= 1 then
                return
            end

            local desc
            if value ~= "" then
                desc = value
            else
                desc = default_desc
            end

            save_project(idx, desc)
            return
        end

        -- Search for the project, if an argument was given
        -- Or ask interactively
        local selected_idx = _find_project_index(list, job.args[2]) or ya.which({ cands = list, silent = false })
        if not selected_idx then
            return
        end

        if action == "load" then
            local selected = list[selected_idx]
            load_project(selected.project, selected.desc)
        elseif action == "delete" then
            delete_project(list[selected_idx].on)
        end
    end,
}
