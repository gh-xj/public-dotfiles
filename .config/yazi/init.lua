require("folder-rules"):setup()
require("full-border"):setup {}
require("relative-motions"):setup {
    show_numbers = "absolute",
    show_motion = true,
    enter_mode = "first",
}

-- Show the username without the hostname.
Header:children_add(function()
    if ya.target_family() ~= "unix" then
        return ""
    end
    return ui.Span(ya.user_name() .. ":"):fg("blue")
end, 500, Header.LEFT)

th.git = th.git or {}
th.git.modified_sign = "M"
th.git.deleted_sign = "D"
require("git"):setup()

require("zoxide"):setup { update_db = true }

-- Keep the existing local JSON state and plugin event names; inherit other options.
require("projects"):setup { save = { method = "lua" } }
