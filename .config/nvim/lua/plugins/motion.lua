return {
  {
    "easymotion/vim-easymotion",
    keys = {
      { "s", "<Plug>(easymotion-s2)", mode = { "n", "v", "o" }, desc = "EasyMotion 2-char" },
    },
    init = function()
      vim.g.EasyMotion_do_mapping = 0
      vim.g.EasyMotion_smartcase = 1
    end,
  },
}
