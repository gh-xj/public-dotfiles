return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bufdelete = { enabled = true },
      input = { enabled = true },
      lazygit = {
        enabled = true,
        win = {
          width = 0.95,
          height = 0.9,
          border = "rounded",
        },
      },
      notifier = {
        enabled = true,
        timeout = 3000,
      },
      picker = {
        enabled = true,
        ui_select = true,
      },
      quickfile = { enabled = true },
    },
  },
}
