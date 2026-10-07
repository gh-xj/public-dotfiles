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

-- Folding defaults. Treesitter folding is enabled per-buffer for supported
-- filetypes so empty startup and unsupported buffers stay cheap.
opt.foldmethod = "manual"
opt.foldexpr = "0"
opt.foldenable = true
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldcolumn = "0"
opt.fillchars:append({ fold = " " })
