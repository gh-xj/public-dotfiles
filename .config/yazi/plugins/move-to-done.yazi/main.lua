-- Move the current selection into the browsing directory's Done folder.
local selected = ya.sync(function()
    local files = {}
    for _, item in pairs(cx.active.selected) do
        files[#files + 1] = item.url or item
    end
    if #files == 0 and cx.active.current.hovered then
        files[1] = cx.active.current.hovered.url
    end
    return cx.active.current.cwd, files
end)

local function notify(message, level)
    ya.notify { title = "Move to Done", content = message, timeout = 5, level = level or "info" }
end

return {
    entry = function()
        local cwd, files = selected()
        if (cwd.spec or cwd.scheme).is_virtual then
            return notify("Move to Done requires a local directory", "warn")
        elseif #files == 0 then
            return notify("No files selected or hovered", "warn")
        end

        -- Search URLs refer to local paths, but mv must receive filesystem paths.
        cwd = Url(tostring(cwd.path or cwd))
        local done = cwd:join("Done")
        local cha = fs.cha(done)
        if cha and (not cha.is_dir or cha.is_link) then
            return notify("Done already exists as a file or symbolic link", "error")
        end
        local ok, err = fs.create("dir_all", done)
        if not ok then
            return notify("Cannot create Done: " .. tostring(err), "error")
        end

        local moved, skipped, failures = 0, 0, {}
        for _, source in ipairs(files) do
            source = Url(tostring(source.path or source))
            local target = done:join(source.name)
            if source == done or fs.cha(target) then
                skipped = skipped + 1
            else
                -- -n makes collisions non-destructive; argv preserves spaces and quotes.
                local output, error = Command("mv")
                    :arg("-n"):arg("--"):arg(tostring(source)):arg(tostring(done))
                    :stdout(Command.PIPED):stderr(Command.PIPED):output()
                if not output or not output.status.success then
                    failures[#failures + 1] = output and output.stderr or tostring(error)
                elseif fs.cha(source) then
                    skipped = skipped + 1
                else
                    moved = moved + 1
                end
            end
        end
        ya.emit("escape", {})
        local summary = string.format("Moved %d; skipped %d existing or ineligible item(s)", moved, skipped)
        if #failures > 0 then
            return notify(summary .. "\n" .. table.concat(failures, "\n"), "error")
        end
        notify(summary, skipped > 0 and "warn" or "info")
    end,
}
