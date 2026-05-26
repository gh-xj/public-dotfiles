local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd
local large_file = require("config.large_file")

autocmd("FileType", {
  group = augroup("xj_treesitter_folds", { clear = true }),
  pattern = { "lua", "vim", "help", "javascript", "typescript", "python", "html", "css", "markdown" },
  callback = function(ev)
    if large_file.is_large_buffer(ev.buf) then
      vim.opt_local.foldmethod = "manual"
      vim.opt_local.foldexpr = "0"
      vim.opt_local.foldcolumn = "0"
      return
    end

    vim.opt_local.foldmethod = "expr"
    vim.opt_local.foldexpr = "v:lua.vim.treesitter.foldexpr()"
    vim.opt_local.foldcolumn = "1"
  end,
})

-- Markdown ergonomics: wrap/prefix helpers (Zed-style) + prose-friendly
-- filetype-local options.
local md_group = augroup("xj_markdown_keymaps", { clear = true })
autocmd("FileType", {
  group = md_group,
  pattern = "markdown",
  callback = function(ev)
    local opts = { buffer = ev.buf, silent = true }
    vim.keymap.set("x", "<leader>mb", 'c**<C-r>"**<Esc>', opts)
    vim.keymap.set("x", "<leader>mi", 'c*<C-r>"*<Esc>', opts)
    vim.keymap.set("x", "<leader>mc", 'c`<C-r>"`<Esc>', opts)
    vim.keymap.set("n", "<leader>ml", "I- <Space><Esc>", opts)
    vim.keymap.set("n", "<leader>mt", "I- [ ] <Esc>", opts)

    -- Prose-friendly buffer/window-local settings.
    vim.opt_local.textwidth = 0

    if large_file.is_large_markdown(ev.buf) then
      -- Large markdown buffers keep the editing keymaps, but skip the expensive
      -- prose niceties that slow redraw and file-open time.
      vim.opt_local.wrap = false
      vim.opt_local.linebreak = false
      vim.opt_local.breakindent = false
      vim.opt_local.conceallevel = 0
      vim.opt_local.concealcursor = ""
      vim.opt_local.spell = false
      vim.opt_local.foldmethod = "manual"
      vim.opt_local.foldexpr = "0"
      vim.opt_local.foldcolumn = "0"
      return
    end

    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"
    vim.opt_local.spell = false
  end,
})

-- Filetype-specific format-on-save (Zed-aligned, not global).
autocmd("BufWritePre", {
  group = augroup("xj_format_on_save", { clear = true }),
  pattern = { "*.go", "*.json" },
  callback = function()
    require("lazy").load({ plugins = { "conform.nvim" } })
    require("conform").format({ lsp_fallback = true, async = false })
  end,
})
