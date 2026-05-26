return {
  -- Browser preview (requires `node` — build step runs `npm install` under the
  -- plugin dir on first load).
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreview", "MarkdownPreviewToggle", "MarkdownPreviewStop" },
    build = function() vim.fn["mkdp#util#install"]() end,
    init = function()
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_theme = "light"
    end,
  },

  -- Clipboard image paste: <leader>ip in a markdown buffer saves the macOS
  -- clipboard PNG to ./assets/ and inserts ![](relative/path). Requires
  -- `pngpaste` on macOS.
  {
    "HakonHarnes/img-clip.nvim",
    ft = { "markdown" },
    opts = {
      default = {
        dir_path = "assets",
        relative_to_current_file = true,
        use_absolute_path = false,
        prompt_for_file_name = false,
        file_name = "%Y%m%d-%H%M%S",
      },
    },
    keys = {
      {
        "<leader>ip",
        function() require("img-clip").paste_image() end,
        mode = "n",
        ft = "markdown",
        desc = "Paste clipboard image as markdown link",
      },
    },
  },

  -- Markdown editing ergonomics: `gs{b|i|c|s}` toggles inline bold/italic/
  -- code/strike, `gl` inserts/edits links, `<M-l><M-{hjkl}>` moves table
  -- cells, `:MDInsertToc` writes a table of contents. `gh` left alone to
  -- not shadow LSP hover (markdown LSP attaches via marksman).
  {
    "tadmccorkle/markdown.nvim",
    ft = { "markdown" },
    opts = {
      mappings = {
        go_curr_heading = false,
      },
    },
  },

  -- LSP / completion / diagnostics inside fenced code blocks. otter parses
  -- the markdown buffer with treesitter and attaches the matching language
  -- server to each ```lang block (lua_ls in ```lua, pyright in ```python,
  -- etc.). Lazy on markdown FileType and skipped for large markdown buffers
  -- to keep open-time cheap.
  {
    "jmbuhr/otter.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {},
    config = function(_, opts)
      require("otter").setup(opts)
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("xj_otter_activate", { clear = true }),
        pattern = "markdown",
        callback = function(ev)
          if require("config.large_file").is_large_markdown(ev.buf) then
            return
          end
          require("otter").activate()
        end,
      })
      if vim.bo.filetype == "markdown"
        and not require("config.large_file").is_large_markdown(0)
      then
        require("otter").activate()
      end
    end,
  },

  -- In-buffer rendered markdown view, reading-first. `render_modes = true`
  -- keeps the rendered view in ALL modes so entering insert does not
  -- swap the whole buffer back to raw markdown. `anti_conceal.enabled =
  -- false` keeps the cursor line rendered so moving over a heading,
  -- table, or link does not flip that line to raw either. Combined,
  -- the view is static like treesitter conceal — never swaps. Heading
  -- backgrounds and CodeBlock / Dash highlight groups are defined in
  -- config/theme.lua's apply_markdown_styles. Web-devicons supplies
  -- the language icon for fenced code blocks.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "nvim-tree/nvim-web-devicons",
    },
    opts = {
      render_modes = true,
      anti_conceal = { enabled = false },
      heading = {
        sign = false,
        icons = { "◉ ", "○ ", "✸ ", "✿ ", "✦ ", "✧ " },
        backgrounds = {
          "Headline1", "Headline2", "Headline3",
          "Headline4", "Headline5", "Headline6",
        },
      },
      code = {
        sign = false,
        style = "normal",
        border = "thick",
        highlight = "CodeBlock",
      },
      pipe_table = {
        preset = "round",
      },
      dash = {
        highlight = "Dash",
      },
    },
  },

  -- List continuation only. Press <CR> on `- item` or `1. item` and the
  -- next line is opened with the right prefix; outdent on empty bullet
  -- ends the list. Replaces mkdnflow which carried this feature alongside
  -- a broken follow-link path. Numbered list auto-renumber is on by
  -- default.
  {
    "dkarter/bullets.vim",
    ft = { "markdown", "text", "gitcommit", "scratch" },
    init = function()
      vim.g.bullets_enabled_file_types = { "markdown", "text", "gitcommit", "scratch" }
      vim.g.bullets_set_mappings = 1
      vim.g.bullets_checkbox_markers = " x"
    end,
  },
}
