require("folder-rules"):setup()

require("full-border"):setup {}

-- * show hostname [Tips | Yazi](https://yazi-rs.github.io/docs/tips/#username-hostname-in-header)
Header:children_add(function()
    if ya.target_family() ~= "unix" then
        return ""
    end
    -- return ui.Span(ya.user_name() .. "@" .. ya.host_name() .. ":"):fg("blue")
    -- note: hide host-name
    return ui.Span(ya.user_name() .. ":"):fg("blue")
end, 500, Header.LEFT)


-- require("relative-motions"):setup({ show_numbers = "absolute", show_motion = true })
require("relative-motions"):setup({ show_numbers = "absolute", show_motion = true, enter_mode = "first" })

-- [llanosrocas/githead.yazi: Git status header for yazi inspired by powerlevel10k](https://github.com/llanosrocas/githead.yazi)
-- require("githead"):setup({})

require("toggle-view")

require("xj-fzf")

require("follow-symlink")

-- todo: how to figure the different layout based on current hover file type -> folder or file
-- require("xj-preview-control").setup()

-- [plugins/git.yazi at main · yazi-rs/plugins](https://github.com/yazi-rs/plugins/tree/main/git.yazi)
th.git = th.git or {}
th.git.modified_sign = "M"
th.git.deleted_sign = "D"

require("git"):setup()

require("zoxide"):setup({ update_db = true })

-- [MasouShizuka/projects.yazi: A yazi plugin that adds the functionality to save and load projects.](https://github.com/MasouShizuka/projects.yazi)
require("projects"):setup({
    save = {
        method = "lua" -- yazi | lua
        -- yazi_load_event = "@projects-load" -- event name when loading projects in `yazi` method
        -- lua_save_path = "",                 -- path of saved file in `lua` method, comment out or assign explicitly
        -- default value:
        -- windows: "%APPDATA%/yazi/state/projects.json"
        -- unix: "~/.local/state/yazi/projects.json"
    },
    last = {
        update_after_save = true,
        update_after_load = true,
        load_after_start = false,
    },
    merge = {
        event = "projects-merge",
        quit_after_merge = false,
    },
    event = {
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
    },
    notify = {
        enable = true,
        title = "Projects",
        timeout = 3,
        level = "info",
    },
})
