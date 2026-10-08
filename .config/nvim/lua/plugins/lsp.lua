return {
  {
    "neovim/nvim-lspconfig",
    opts = {
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

  -- Nix-provided tools win over Mason's copies.
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
