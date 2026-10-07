return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = {
      options = { theme = "auto" },
      sections = {
        lualine_b = { "branch", {
          "diff",
          source = function()
            local s = vim.b.gitsigns_status_dict
            if s then
              return { added = s.added, modified = s.changed, removed = s.removed }
            end
          end,
        }, "diagnostics" },
      },
    },
  },

  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    config = function()
      require("bufferline").setup({})
    end,
  },

  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = { delay = 300 },
  },

  {
    "folke/trouble.nvim",
    cmd = { "Trouble", "TroubleToggle" },
    config = true,
  },

  {
    "machakann/vim-highlightedyank",
    event = "TextYankPost",
  },
}
