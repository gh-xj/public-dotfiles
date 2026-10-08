return {
  -- Flash keeps f/F/T, `S` and remote jumps; `s` stays EasyMotion and `t`
  -- scrolls (config/keymaps.lua). `,` is the localleader, so it is not a repeat key.
  {
    "folke/flash.nvim",
    opts = { modes = { char = { keys = { "f", "F", "T", ";" } } } },
    keys = { { "s", mode = { "n", "x", "o" }, false } },
  },
  {
    "easymotion/vim-easymotion",
    keys = {
      { "s", "<Plug>(easymotion-s2)", mode = { "n", "x", "o" }, desc = "EasyMotion 2-char" },
    },
    init = function()
      vim.g.EasyMotion_do_mapping = 0
      vim.g.EasyMotion_smartcase = 1
    end,
  },

  -- Zed-aligned multicursor; Esc clears cursors only while some exist.
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    keys = {
      { "gl", function() require("multicursor-nvim").matchAddCursor(1) end, mode = { "n", "x" }, desc = "Add cursor at next match" },
      { "gL", function() require("multicursor-nvim").matchAddCursor(-1) end, mode = { "n", "x" }, desc = "Add cursor at previous match" },
      { "g>", function() require("multicursor-nvim").matchSkipCursor(1) end, mode = { "n", "x" }, desc = "Skip to next match" },
      { "g<", function() require("multicursor-nvim").matchSkipCursor(-1) end, mode = { "n", "x" }, desc = "Skip to previous match" },
      { "ga", function() require("multicursor-nvim").matchAllAddCursors() end, mode = { "n", "x" }, desc = "Cursor at every match" },
    },
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()
      mc.addKeymapLayer(function(set)
        set("n", "<Esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end)
      end)
    end,
  },

  { "kylechui/nvim-surround", event = "VeryLazy", opts = {} },

  -- Yazi float for heavy file operations; the Snacks explorer is <leader>e.
  {
    "mikavilpas/yazi.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = { { "<C-e>", "<cmd>Yazi<cr>", desc = "Yazi" } },
    opts = {
      open_for_directories = false,
      floating_window_scaling_factor = 0.9,
      keymaps = { show_help = "?" },
    },
  },

  {
    "folke/snacks.nvim",
    opts = {
      bigfile = { size = 512 * 1024 },
    },
  },
}
