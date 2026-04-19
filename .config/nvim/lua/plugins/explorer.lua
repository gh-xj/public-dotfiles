return {
  {
    "mikavilpas/yazi.nvim",
    cmd = "Yazi",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      open_for_directories = true,
      floating_window_scaling_factor = 0.9,
      keymaps = {
        show_help = "?",
      },
    },
  },
}
