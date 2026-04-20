-- Leader must be set before lazy.nvim loads plugin keys.
vim.g.mapleader = ","
vim.g.maplocalleader = ","

-- Disable built-in plugins we don't use. Saves a couple ms at startup and
-- avoids surprise default mappings (e.g. netrw grabbing directory buffers).
for _, plugin in ipairs({
  "netrw", "netrwPlugin", "netrwSettings", "netrwFileHandlers",
  "matchit", "matchparen",
  "tarPlugin", "tar", "zipPlugin", "zip", "gzip",
  "2html_plugin", "tohtml", "tutor", "tutor_mode_plugin",
  "spellfile_plugin",
}) do
  vim.g["loaded_" .. plugin] = 1
end
vim.g.loaded_nvim_net_plugin = true
vim.g.loaded_remote_plugins = true

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("config.options")
require("config.machine")

require("lazy").setup("plugins", {
  install = { colorscheme = { "one" } },
  change_detection = { notify = false },
})

require("config.keymaps")
require("config.autocmds")
require("config.theme")
