return {
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo", "Format" },
    opts = {
      formatters_by_ft = {
        go = { "gofmt" },
        json = { "jq" },
        markdown = { "prettier" },
      },
    },
  },
}
