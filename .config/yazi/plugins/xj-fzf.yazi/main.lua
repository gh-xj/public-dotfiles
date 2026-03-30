local M = {}

local state = ya.sync(function()
    return cx.active.current.cwd
end)

function M:entry()
    local cwd = state()
    
    local _permit = ui.hide()

    local FZF_DEFAULT_COMMAND = 'rg --files --no-ignore --hidden --follow --glob "!{.git,node_modules}/*" 2> /dev/null'

    local child, err = Command("fzf")
        :cwd(tostring(cwd))
        :env("FZF_DEFAULT_COMMAND", FZF_DEFAULT_COMMAND)
        :stdin(Command.INHERIT)
        :stdout(Command.PIPED)
        :spawn()

    if not child then
        return ya.notify { title = "Fzf", content = "Failed to start fzf: " .. tostring(err), timeout = 5, level = "error" }
    end

    local output, err = child:wait_with_output()
    if not output then
        return ya.notify { title = "Fzf", content = "Cannot read fzf output: " .. tostring(err), timeout = 5, level = "error" }
    elseif not output.status.success and output.status.code ~= 130 then
        return ya.notify { title = "Fzf", content = "fzf exited with code " .. tostring(output.status.code), timeout = 5, level = "error" }
    end

    local target = output.stdout:gsub("\n$", "")
    if target ~= "" then
        local url = Url(target)
        if url.is_absolute then
            ya.emit(fs.cha(url) and fs.cha(url).is_dir and "cd" or "reveal", { url, raw = true })
        else
            local full_url = cwd:join(url)
            local cha = fs.cha(full_url)
            ya.emit(cha and cha.is_dir and "cd" or "reveal", { full_url, raw = true })
        end
    end
end

return M
