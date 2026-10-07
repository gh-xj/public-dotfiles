return {
  {
    "mfussenegger/nvim-lint",
    event = "User XjSmallMarkdown",
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = { markdown = { "markdownlint-cli2" } }
      vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("xj_nvim_lint", { clear = true }),
        callback = function() lint.try_lint() end,
      })
    end,
  },
}
