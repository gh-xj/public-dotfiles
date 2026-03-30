--- @sync entry
local function setup()
    ps.sub("hover", function()
        local file = cx.active.current.hovered

        local R = rt.mgr.ratio

        local new_ratio = { 1, 4, 3 }
        -- if not dir, then do not preview
        if file == nil or not file.cha.is_dir then
            new_ratio[2] = new_ratio[3] + new_ratio[2]
            new_ratio[3] = 0
        end
        -- --> if new_ratio == old_ratio, then do nothing
        local old_ratio = { R.parent, R.current, R.preview }
        if old_ratio[1] == new_ratio[1] and old_ratio[2] == new_ratio[2] and old_ratio[3] == new_ratio[3] then
            return
        end

        Tab.layout = function(self)
            local all = new_ratio[1] + new_ratio[2] + new_ratio[3]
            self._chunks = ui.Layout()
                :direction(ui.Layout.HORIZONTAL)
                :constraints({
                    ui.Constraint.Ratio(new_ratio[1], all),
                    ui.Constraint.Ratio(new_ratio[2], all),
                    ui.Constraint.Ratio(new_ratio[3], all),
                })
                :split(self._area)
        end

        ya.emit("app:resize", {})
    end)
end

--- @sync entry

return { setup = setup }
