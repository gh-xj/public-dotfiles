return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = { options = { theme = "auto" } },
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
