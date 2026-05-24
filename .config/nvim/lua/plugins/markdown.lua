local function load_small_markdown_plugin(group_name, plugin_name, module_name, after_load)
  return function()
    local group = vim.api.nvim_create_augroup(group_name, { clear = true })
    vim.api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = "markdown",
      callback = function(ev)
        local large_file = require("config.large_file")
        if large_file.is_large_markdown(ev.buf) then
          return
        end

        local already_loaded = package.loaded[module_name] ~= nil
        require("lazy").load({ plugins = { plugin_name } })

        if not already_loaded and after_load then
          after_load()
        end
      end,
    })
  end
end

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

  -- Per-level visual differentiation for H1–H6: extmark backgrounds + a thin
  -- separator under each heading line. Colors follow the active colorscheme,
  -- so the auto dark/light switch in config/theme.lua keeps working. Set
  -- fat_headlines = true if you want the chunkier "block" look.
  {
    "lukas-reineke/headlines.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      markdown = {
        fat_headlines = false,
      },
    },
  },

  -- Prose-writing helpers: auto list continuation, task toggle, internal
  -- wiki-style link following. Folds/conceal disabled so treesitter owns them.
  {
    "jakewvincent/mkdnflow.nvim",
    cmd = { "Mkdnflow" },
    init = load_small_markdown_plugin("xj_mkdnflow_lazy", "mkdnflow.nvim", "mkdnflow"),
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
