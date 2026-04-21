local ts_filetypes = {
  "lua",
  "vim",
  "help",
  "javascript",
  "typescript",
  "python",
  "html",
  "css",
  "markdown",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    ft = ts_filetypes,
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      local ok, ts = pcall(require, "nvim-treesitter.configs")
      if not ok then
        ok, ts = pcall(require, "nvim-treesitter.config")
      end
      if not ok then
        vim.notify("[nvim] nvim-treesitter is not installed.", vim.log.levels.WARN)
        return
      end
      ts.setup({
        ensure_installed = {
          "lua", "vim", "vimdoc",
          "javascript", "typescript",
          "python",
          "html", "css",
          "markdown", "markdown_inline",
        },
        highlight = {
          enable = true,
          disable = function(_, buf)
            return require("config.large_file").is_large_buffer(buf)
          end,
        },
        textobjects = {
          select = {
            enable = true,
            lookahead = true,
            keymaps = {
              ["af"] = "@function.outer",
              ["if"] = "@function.inner",
              ["ac"] = "@class.outer",
              ["ic"] = "@class.inner",
              ["aa"] = "@parameter.outer",
              ["ia"] = "@parameter.inner",
            },
          },
          move = {
            enable = true,
            set_jumps = true,
            goto_next_start = {
              ["]m"] = "@function.outer",
              ["]]"] = "@class.outer",
            },
            goto_next_end = {
              ["]M"] = "@function.outer",
              ["]["] = "@class.outer",
            },
            goto_previous_start = {
              ["[m"] = "@function.outer",
              ["[["] = "@class.outer",
            },
            goto_previous_end = {
              ["[M"] = "@function.outer",
              ["[]"] = "@class.outer",
            },
          },
        },
      })
    end,
  },
}
