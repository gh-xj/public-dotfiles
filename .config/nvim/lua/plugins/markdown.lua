return {
  -- In-buffer markdown rendering: headings with icons, code block borders,
  -- task-list symbols, table alignment, bullet typography.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {},
  },

  -- Browser preview (requires `node` — build step runs `npm install` under the
  -- plugin dir on first load).
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreview", "MarkdownPreviewToggle", "MarkdownPreviewStop" },
    ft = { "markdown" },
    build = function() vim.fn["mkdp#util#install"]() end,
    init = function()
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_theme = "light"
    end,
  },

  -- Prose-writing helpers: auto list continuation, task toggle, internal
  -- wiki-style link following. Folds/conceal disabled so treesitter owns them.
  {
    "jakewvincent/mkdnflow.nvim",
    ft = "markdown",
    opts = {
      modules = {
        bib = false,
        folds = false,
      },
      mappings = {
        -- Leave most of mkdnflow's defaults alone; only explicit overrides go
        -- here if they clash with your existing bindings.
      },
    },
  },
}
