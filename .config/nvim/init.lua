-- LazyVim base with personal overrides. Leaders are set again in
-- config/options.lua because LazyVim assigns its own defaults first.
vim.g.mapleader = " "
vim.g.maplocalleader = ","

require("config.machine")
require("config.lazy")
