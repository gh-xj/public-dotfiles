--- @sync entry
-- Toggle different views on/off: parent, current, preview
local function entry(st, job)
    -- local args = job.args or job
    -- local action = args[1]

    local R = rt.mgr.ratio
    job = type(job) == "string" and { args = { job } } or job
    local action = job.args[1]

    if not action then
        return
    end

    if st.view == nil then
        st.old_parent = R.parent
        st.old_current = R.current
        st.old_preview = R.preview

        -- Get current tab ratios
        local all_old = st.old_parent + st.old_current + st.old_preview
        local area = ui.Rect { x = 0, y = 0, w = all_old, h = 10 }
        local tab = Tab:new(area, cx.active)
        st.parent = tab._chunks[1].w
        st.current = tab._chunks[2].w
        st.preview = tab._chunks[3].w
        st.layout = Tab.layout
        st.view = true -- initialized
    end

    if action == "parent" then
        if st.parent > 0 then
            st.parent = 0
        else
            st.parent = st.old_parent
        end
    elseif action == "current" then
        if st.current > 0 then
            st.current = 0
        else
            st.current = st.old_current
        end
    elseif action == "preview" then
        if st.preview > 0 then
            st.current = 7
            st.preview = 0
        else
            st.current = 4
            st.preview = 3
        end
    else
        return
    end
    Tab.layout = function(self)
        local all = st.parent + st.current + st.preview
        self._chunks = ui.Layout()
            :direction(ui.Layout.HORIZONTAL)
            :constraints({
                ui.Constraint.Ratio(st.parent, all),
                ui.Constraint.Ratio(st.current, all),
                ui.Constraint.Ratio(st.preview, all),
            })
            :split(self._area)
    end

    ya.emit("app:resize", {})
end

local function enabled(st) return st.view ~= nil end

return { entry = entry, enabled = enabled }
