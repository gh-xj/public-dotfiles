local hovered = ya.sync(function()
    local h = cx.active.current.hovered
    if not h then
        return {}
    end

    return {
        url = h.url,
        link_to = h.link_to,
        is_dir = h.cha.is_dir,
        unique = #cx.active.current.files == 1,
    }
end)

return {
    entry = function()
        local h = hovered()
        if not h then
            ya.err("No hovered item")
            return
        end

        local original_url = h.link_to
        if not original_url then
            ya.err("No link target")
            return
        end

        local cha, err = fs.cha(original_url)
        if err then
            ya.err(err)
        end

        ya.manager_emit("reveal", { original_url })
        -- if cha.is_dir then
        --     ya.manager_emit("cd", { original_url })
        -- else
        --     ya.manager_emit("reveal", { original_url })
        -- end
    end,
}
