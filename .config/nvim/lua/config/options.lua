-- Loaded by LazyVim after its own defaults.
vim.g.mapleader = " "
vim.g.maplocalleader = ","

-- Format on save is opt-in per filetype (Go, JSON); see autocmds.lua.
vim.g.autoformat = false
-- No scroll/resize animations: they read as input lag in a many-pane tmux workflow.
vim.g.snacks_animate = false

local opt = vim.opt
opt.relativenumber = false
opt.scrolloff = 8
opt.spell = false
vim.g.trouble_lualine = false -- symbols move to the winbar breadcrumbs (plugins/ui.lua)
