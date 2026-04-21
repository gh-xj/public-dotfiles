return {
  {
    "stevearc/conform.nvim",
    cmd = { "ConformInfo" },
    opts = {
      formatters_by_ft = {
        go = { "gofmt" },
        json = { "jq" },
        markdown = { "prettier" },
      },
    },
  },
}
