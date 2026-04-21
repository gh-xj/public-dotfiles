local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd
local large_file = require("config.large_file")

-- Auto-close NERDTree when it's the last window.
autocmd("BufEnter", {
  group = augroup("nvim_nerdtree_autoclose", { clear = true }),
  callback = function()
    if vim.fn.winnr("$") == 1
      and vim.fn.exists("b:NERDTree") == 1
      and vim.b.NERDTree
      and vim.b.NERDTree.isTabTree
      and vim.b.NERDTree:isTabTree() then
      vim.cmd("q")
    end
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
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
    vim.opt_local.conceallevel = 2
    vim.opt_local.concealcursor = "nc"
    vim.opt_local.spell = false
    vim.opt_local.textwidth = 0

    if not large_file.is_large_markdown(ev.buf) then
      return
    end

    -- Large markdown buffers keep the editing keymaps, but skip the expensive
    -- prose niceties that slow redraw and file-open time.
    vim.opt_local.conceallevel = 0
    vim.opt_local.spell = false
    vim.opt_local.foldmethod = "manual"
    vim.opt_local.foldexpr = "0"
  end,
})

-- Filetype-specific format-on-save (Zed-aligned, not global).
autocmd("BufWritePre", {
  group = augroup("xj_format_on_save", { clear = true }),
  pattern = { "*.go", "*.json" },
  callback = function()
    require("conform").format({ lsp_fallback = true, async = false })
  end,
})
