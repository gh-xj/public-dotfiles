local server_list = {
  "lua_ls", "ts_ls", "pyright", "gopls",
  "jsonls", "yamlls", "marksman", "bashls",
}

local lsp_filetypes = {
  "lua",
  "javascript", "javascriptreact",
  "typescript", "typescriptreact",
  "python",
  "go",
  "json", "jsonc",
  "yaml",
  "sh", "bash", "zsh",
}

return {
  {
    "williamboman/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    config = true,
  },

  {
    "williamboman/mason-lspconfig.nvim",
    dependencies = { "williamboman/mason.nvim", "neovim/nvim-lspconfig" },
    event = "VeryLazy",
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = server_list,
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    ft = lsp_filetypes,
    init = function()
      local group = vim.api.nvim_create_augroup("xj_lsp_markdown_lazy", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = "markdown",
        callback = function(ev)
          if require("config.large_file").is_large_markdown(ev.buf) then
            return
          end

          require("lazy").load({ plugins = { "nvim-lspconfig" } })
        end,
      })
    end,
    config = function()
      local capabilities = {}
      local current_buf = vim.api.nvim_get_current_buf()
      local is_large_markdown = vim.bo[current_buf].filetype == "markdown"
        and require("config.large_file").is_large_markdown(current_buf)
      if not is_large_markdown then
        local ok, blink = pcall(require, "blink.cmp")
        capabilities = ok and blink.get_lsp_capabilities() or {}
      end

      local enabled_servers = vim.deepcopy(server_list)
      if is_large_markdown then
        enabled_servers = vim.tbl_filter(function(name)
          return name ~= "marksman"
        end, enabled_servers)
      end

      for _, name in ipairs(server_list) do
        vim.lsp.config(name, { capabilities = capabilities })
      end
      vim.lsp.enable(enabled_servers)

      -- Zed-aligned LSP keymaps, set on attach so they only exist where a
      -- server is actually answering.
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("xj_lsp_keymaps", { clear = true }),
        callback = function(ev)
          local buf = ev.buf
          local function nmap(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, desc = desc })
          end
          nmap("gd", vim.lsp.buf.definition, "LSP: goto definition")
          nmap("gD", vim.lsp.buf.declaration, "LSP: goto declaration")
          nmap("gy", vim.lsp.buf.type_definition, "LSP: goto type definition")
          nmap("gI", vim.lsp.buf.implementation, "LSP: goto implementation")
          nmap("gA", vim.lsp.buf.references, "LSP: all references")
          nmap("gh", vim.lsp.buf.hover, "LSP: hover")
          nmap("g.", vim.lsp.buf.code_action, "LSP: code action")
          nmap("<leader>rn", vim.lsp.buf.rename, "LSP: rename")
        end,
      })
    end,
  },

  {
    "saghen/blink.cmp",
    version = "1.*",
    event = "InsertEnter",
    opts = {
      keymap = {
        preset = "enter",
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
      },
      completion = {
        accept = { auto_brackets = { enabled = true } },
        documentation = { auto_show = true, auto_show_delay_ms = 150 },
      },
      sources = {
        default = { "lsp", "path", "snippets", "buffer" },
      },
      signature = { enabled = true },
    },
  },
}
