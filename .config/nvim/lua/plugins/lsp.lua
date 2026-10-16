local function without_mason_dependencies(plugin)
  plugin.dependencies = vim.tbl_filter(function(name)
    return name ~= "mason.nvim" and name ~= "mason-lspconfig.nvim"
  end, plugin.dependencies or {})
end

return {
  {
    "neovim/nvim-lspconfig",
    init = function(plugin)
      -- Nix provides the primary servers. Keep installed Mason tools last on
      -- PATH, but keep Mason's registry off every file-open path.
      without_mason_dependencies(plugin)
      local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
      local path = vim.split(vim.env.PATH or "", ":", { plain = true })
      if not vim.tbl_contains(path, mason_bin) then
        vim.env.PATH = table.concat(vim.list_extend(path, { mason_bin }), ":")
      end
    end,
    opts = {
      setup = {
        marksman = function(server, opts)
          vim.lsp.config(server, opts)
          local group = vim.api.nvim_create_augroup("xj_deferred_marksman", { clear = true })
          vim.api.nvim_create_autocmd({ "CursorHold", "InsertEnter" }, {
            group = group,
            callback = function(event)
              if vim.tbl_contains({ "markdown", "markdown.mdx" }, vim.bo[event.buf].filetype) then
                vim.lsp.enable(server)
                vim.api.nvim_del_augroup_by_id(group)
              end
            end,
          })
          return true
        end,
      },
      servers = {
        -- Zed-aligned g-keys; K is the five-line jump (config/keymaps.lua).
        ["*"] = {
          keys = {
            { "K", false },
            -- ga is multicursor's select-all; drop LazyVim's ga* call hierarchy keys.
            { "gai", false },
            { "gao", false },
            { "gh", function() return vim.lsp.buf.hover() end, desc = "Hover" },
            { "gA", vim.lsp.buf.references, desc = "References", has = "references" },
            { "g.", vim.lsp.buf.code_action, desc = "Code Action", mode = { "n", "x" }, has = "codeAction" },
          },
        },
        -- Nix packages these servers (packages/dev.nix); Mason fills the rest.
        bashls = { mason = false },
        gopls = { mason = false },
        jsonls = { mason = false },
        marksman = { mason = false },
        nil_ls = { mason = false },
        pyright = { mason = false },
      },
    },
  },

  -- Existing Mason tools stay available through PATH; installation and the
  -- registry UI load explicitly with :Mason instead of every BufRead.
  { "mason-org/mason-lspconfig.nvim", enabled = false },
  { "mfussenegger/nvim-lint", init = without_mason_dependencies },
  { "stevearc/conform.nvim", init = without_mason_dependencies },
  { "mason-org/mason.nvim", opts = { PATH = "append" } },

  -- Format on save is enabled only for Go and JSON (config/autocmds.lua);
  -- these formatters match Zed.
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        go = { "gofmt" },
        json = { "jq" },
      },
    },
  },

  -- tmux owns Ctrl-Space (pane zoom), so Ctrl-n opens the menu when it is closed.
  {
    "saghen/blink.cmp",
    opts = {
      keymap = {
        ["<C-n>"] = {
          function(cmp)
            if cmp.is_visible() then
              return cmp.select_next()
            end
            return cmp.show()
          end,
          "fallback",
        },
      },
    },
  },
}
