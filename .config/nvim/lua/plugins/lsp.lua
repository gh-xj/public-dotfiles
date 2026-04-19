local server_list = {
  "lua_ls", "ts_ls", "pyright", "gopls",
  "jsonls", "yamlls", "marksman", "bashls",
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
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = server_list,
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "hrsh7th/cmp-nvim-lsp" },
    config = function()
      local ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
      local capabilities = ok and cmp_lsp.default_capabilities() or {}

      local function legacy_setup(server_name)
        local ok_lsp, lspconfig = pcall(require, "lspconfig")
        if not ok_lsp then return end
        local candidates = { server_name }
        if server_name == "ts_ls" then
          table.insert(candidates, "tsserver")
        elseif server_name == "tsserver" then
          table.insert(candidates, "ts_ls")
        end
        for _, name in ipairs(candidates) do
          local entry = lspconfig[name]
          if type(entry) == "table" and type(entry.setup) == "function" then
            entry.setup({ capabilities = capabilities })
            return
          end
        end
      end

      if vim.lsp and vim.lsp.config and vim.lsp.enable then
        for _, name in ipairs(server_list) do
          pcall(vim.lsp.config, name, { capabilities = capabilities })
        end
        pcall(vim.lsp.enable, server_list)
      else
        for _, name in ipairs(server_list) do
          legacy_setup(name)
        end
      end

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
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
    },
    config = function()
      local cmp = require("cmp")
      local ok_snip, luasnip = pcall(require, "luasnip")

      cmp.setup({
        snippet = {
          expand = function(args)
            if ok_snip then luasnip.lsp_expand(args.body) end
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
        }, {
          { name = "buffer" },
        }),
      })
    end,
  },
}
