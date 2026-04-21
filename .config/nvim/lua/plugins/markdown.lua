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
  -- In-buffer markdown rendering: headings with icons, code block borders,
  -- task-list symbols, table alignment, bullet typography.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    cmd = { "RenderMarkdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    init = load_small_markdown_plugin(
      "xj_render_markdown_lazy",
      "render-markdown.nvim",
      "render-markdown",
      function()
        local ok, render_markdown = pcall(require, "render-markdown")
        if ok and type(render_markdown.enable) == "function" then
          render_markdown.enable()
        end
      end
    ),
    opts = function()
      local large_file = require("config.large_file")
      return {
        max_file_size = large_file.max_markdown_megabytes(),
        ignore = function(buf)
          return large_file.is_large_markdown(buf)
        end,
        -- Avoid eagerly loading nvim-cmp/LuaSnip just to get markdown checkbox
        -- and callout completion hooks.
        completions = {
          lsp = { enabled = true },
        },
      }
    end,
  },

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
