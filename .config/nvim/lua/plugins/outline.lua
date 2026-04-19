return {
  {
    "stevearc/aerial.nvim",
    cmd = { "AerialToggle", "AerialOpen", "AerialClose" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      backends = { "lsp", "treesitter", "markdown", "man" },
      layout = {
        default_direction = "right",
        min_width = 25,
        max_width = 40,
      },
      close_on_select = true,
      show_guides = true,
      filter_kind = false,
    },
  },
}
