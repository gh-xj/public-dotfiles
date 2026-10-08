-- One Dark / One Light to match Ghostty and Zed. The variant follows
-- 'background', which Nvim tracks from the terminal (see config/autocmds.lua).
return {
  { "folke/tokyonight.nvim", enabled = false },
  { "catppuccin/nvim", name = "catppuccin", enabled = false },
  {
    "olimorris/onedarkpro.nvim",
    lazy = false,
    priority = 1000,
    opts = {},
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = function()
        vim.cmd.colorscheme(vim.o.background == "light" and "onelight" or "onedark")
      end,
    },
  },
}
