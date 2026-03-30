-- Get selected files in sync context
local get_selected_files = ya.sync(function()
    local files = {}

    if #cx.active.selected > 0 then
        for _, url in pairs(cx.active.selected) do
            table.insert(files, tostring(url))
        end
    elseif cx.active.current.hovered then
        table.insert(files, tostring(cx.active.current.hovered.url))
    end

    return files
end)

local function entry()
    -- Get files to move
    local files_to_move = get_selected_files()

    if #files_to_move == 0 then
        ya.notify({
            title = "Move to Done",
            content = "No files selected or hovered",
            timeout = 3,
            level = "error",
        })
        return
    end

    -- Create command with base arguments
    local command = Command("xj_ops")
        :arg("task")
        :arg("move_to_done")

    -- Add each file as a separate --source_paths flag
    for _, file_path in ipairs(files_to_move) do
        command:arg("--source_paths=" .. file_path)
    end

    -- Configure output capture
    command:stdout(Command.PIPED):stderr(Command.PIPED)

    -- Execute the command
    local output, err = command:output()

    if err then
        ya.notify({
            title = "Move to Done - Error",
            content = "Error executing command: " .. err,
            timeout = 5,
            level = "error",
        })
        return
    end

    if not output.status.success then
        ya.notify({
            title = "Move to Done - Failed",
            content = output.stderr or "Command failed with no error message",
            timeout = 5,
            level = "error",
        })
        return
    end

    -- Command succeeded
    ya.notify({
        title = "Move to Done",
        content = output.stdout or "Files moved successfully",
        timeout = 3,
        level = "info",
    })

    -- Clear selection and refresh
    ya.mgr_emit("escape", {})
end

return { entry = entry }
