return {
  { "windwp/nvim-autopairs", event = "InsertEnter", config = true },
  { "numToStr/Comment.nvim", event = "VeryLazy", config = true },
  { "kylechui/nvim-surround", event = "VeryLazy", config = true },
  {
    "chrisgrieser/nvim-various-textobjs",
    event = "VeryLazy",
    opts = {
      keymaps = { useDefaults = true },
    },
  },
}
