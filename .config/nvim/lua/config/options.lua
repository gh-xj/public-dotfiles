local opt = vim.opt

opt.clipboard = "unnamedplus"
opt.expandtab = true
opt.tabstop = 2
opt.shiftwidth = 2
opt.scrolloff = 8
opt.number = true
opt.termguicolors = true
opt.undofile = true
opt.timeout = true
opt.timeoutlen = 300
opt.ttimeout = true
opt.ttimeoutlen = 10

-- Search
opt.hlsearch = true
opt.incsearch = false
opt.ignorecase = true
opt.smartcase = true

vim.g.highlightedyank_highlight_duration = 300

-- Folding — treesitter-based, start fully unfolded (Zed-aligned).
opt.foldmethod = "expr"
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
opt.foldenable = true
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldcolumn = "1"
opt.fillchars:append({ fold = " " })
