local function setup()
    ps.sub("cd", function()
        local cwd = cx.active.current.cwd

        if cwd:ends_with("Downloads") then
            ya.mgr_emit("sort", { "mtime", reverse = true, dir_first = false })
            ya.mgr_emit("linemode", { "mtime" })
        else
            ya.mgr_emit("sort", { "natural", reverse = false, dir_first = true })
            ya.mgr_emit("linemode", { "size" })
        end

        local url_str = tostring(cwd)

        -- if url_str:find("doc-todo", 1, true) then
        --     ya.mgr_emit("sort", { "mtime", reverse = true, dir_first = false })
        --     ya.mgr_emit("linemode", { "none" })
        -- end

        -- NOTE: the search_do command in (https://yazi-rs.github.io/docs/configuration/keymap/#mgr.search)
        -- Only apply to doc-todo/202x/ folder, not subfolders
        local match = url_str:match("doc%-todo/(202%d)/?$")
        if match then
            ya.mgr_emit("sort", { "mtime", reverse = true, dir_first = false })
            ya.mgr_emit("search_do", { "fd", args = "-d 2" })
            -- search fd
        end

        -- local parent_dir = cwd.parent and tostring(cwd.parent)
        -- if parent_dir and parent_dir:find("doc%-todo$") then
        --     -- This is a directory directly under doc-todo
        --     ya.mgr_emit("sort", { "natural", reverse = false, dir_first = true })
        --     ya.mgr_emit("linemode", { "size" })
        -- end
    end)
end

return { setup = setup }
