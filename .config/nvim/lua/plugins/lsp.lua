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

local function prepend_mason_bin()
  local mason_bin = vim.fs.joinpath(vim.fn.stdpath("data"), "mason", "bin")
  if vim.fn.isdirectory(mason_bin) == 0 then
    return
  end

  local separator = vim.fn.has("win32") == 1 and ";" or ":"
  local path = vim.env.PATH or ""
  if not vim.list_contains(vim.split(path, separator, { plain = true }), mason_bin) then
    vim.env.PATH = mason_bin .. separator .. path
  end
end

return {
  {
    "williamboman/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate" },
    init = prepend_mason_bin,
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
    event = "User XjSmallMarkdown",
    config = function()
      local ok, blink = pcall(require, "blink.cmp")
      local capabilities = ok and blink.get_lsp_capabilities() or {}

      for _, name in ipairs(server_list) do
        local config = { capabilities = capabilities }
        if name == "marksman" then
          config.root_dir = function(buf, on_dir)
            if require("config.large_file").is_large_markdown(buf) then
              return
            end
            on_dir(vim.fs.root(buf, { ".marksman.toml", ".git" }))
          end
        end
        vim.lsp.config(name, config)
      end
      vim.lsp.enable(server_list)

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
