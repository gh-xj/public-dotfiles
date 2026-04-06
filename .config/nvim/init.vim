" ============================================================================
" ========================= GENERAL SETTINGS =================================
" ============================================================================
set nocompatible
set clipboard=unnamedplus
set expandtab                   " Use spaces instead of tabs
set tabstop=2 shiftwidth=2      " Set tab width
set scrolloff=8                 " Keep cursor away from screen edge
set termguicolors               " Better color support
set undofile                    " Persistent undo history
set timeout
set timeoutlen=300
set ttimeout
set ttimeoutlen=10

" ============================================================================
" ========================= MACHINE-SPECIFIC CONFIG ==========================
" ============================================================================
let s:machine_specific = expand('~/.config/nvim/_machine_specific.vim')
let s:machine_specific_default = expand('~/.config/nvim/_machine_specific_default.vim')

if !filereadable(s:machine_specific) && filereadable(s:machine_specific_default)
  silent! execute '!cp ' . shellescape(s:machine_specific_default) . ' ' . shellescape(s:machine_specific)
endif

if filereadable(s:machine_specific)
  execute 'source ' . fnameescape(s:machine_specific)
endif

function! s:ReloadMachineSpecificConfig()
  if filereadable(s:machine_specific)
    execute 'source ' . fnameescape(s:machine_specific)
    echo 'Reloaded machine-specific nvim config.'
  else
    echo 'No machine-specific config found: ' . s:machine_specific
  endif
endfunction

command! NvimMachineReload call s:ReloadMachineSpecificConfig()

" ============================================================================
" ========================= PLUGIN MANAGER ==================================
" ============================================================================
" Install vim-plug if not found
if empty(glob('~/.config/nvim/autoload/plug.vim'))
  silent !curl -fLo ~/.config/nvim/autoload/plug.vim --create-dirs
    \ https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
endif

" Run PlugInstall if there are missing plugins
autocmd VimEnter * if len(filter(values(g:plugs), '!isdirectory(v:val.dir)'))
  \| PlugInstall --sync | source $MYVIMRC
\| endif

call plug#begin('~/.config/nvim/plugged')

" Motion and Navigation
Plug 'easymotion/vim-easymotion'            " Quick navigation (instead of leap)

" File Explorer
Plug 'preservim/nerdtree'                   " File system explorer
Plug 'ryanoasis/vim-devicons'               " Icons for NERDTree
Plug 'mikavilpas/yazi.nvim'                 " Yazi file manager integration

" Fuzzy Finding
Plug 'nvim-lua/plenary.nvim'                " Dependency
Plug 'nvim-telescope/telescope.nvim'        " Fuzzy finder

" Highlighting and Syntax
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}

" LSP and Completion
Plug 'neovim/nvim-lspconfig'                " LSP configuration
Plug 'williamboman/mason.nvim'              " LSP installer
Plug 'williamboman/mason-lspconfig.nvim'    " LSP config integration
Plug 'hrsh7th/nvim-cmp'                     " Completion engine
Plug 'hrsh7th/cmp-nvim-lsp'                 " LSP completion
Plug 'L3MON4D3/LuaSnip'                     " Snippet engine
Plug 'saadparwaiz1/cmp_luasnip'             " Snippet completion

" Git
Plug 'lewis6991/gitsigns.nvim'              " Git status in gutter

" Code Assistance
Plug 'windwp/nvim-autopairs'                " Auto-close pairs
Plug 'numToStr/Comment.nvim'                " Quick commenting
Plug 'kylechui/nvim-surround'               " Surroundings

" UI Enhancements
Plug 'nvim-lualine/lualine.nvim'            " Status line
Plug 'akinsho/bufferline.nvim'              " Buffer line
Plug 'folke/which-key.nvim'                 " Keybinding help
Plug 'folke/trouble.nvim'                   " Better diagnostics
Plug 'stevearc/conform.nvim'                " Formatting
Plug 'mrjones2014/smart-splits.nvim'        " Neovim/tmux split navigation
Plug 'machakann/vim-highlightedyank'        " Highlight yanked text

" Colorschemes
Plug 'rakr/vim-one'

call plug#end()

" ============================================================================
" ========================= PLUGIN CONFIGURATION ============================
" ============================================================================
" EasyMotion configuration
let g:EasyMotion_do_mapping = 0 " Disable default mappings
" Use 's' for 2-character search
map s <Plug>(easymotion-s2)

" NERDTree Configuration
let g:NERDTreeShowHidden = 1
let g:NERDTreeMinimalUI = 1
let g:NERDTreeIgnore = ['\.git$', '\.idea$', '\.vscode$', '\.history$', 'node_modules']
let g:NERDTreeStatusline = ''
" Auto close NERDTree when it's the last window
autocmd BufEnter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif


" Basic plugin initialization
lua << EOF
-- Basic setup for plugins
local function safe_require(name)
  local ok, mod = pcall(require, name)
  if not ok then
    vim.notify('[nvim] Failed to load plugin module "' .. name .. '": ' .. tostring(mod))
    return nil
  end
  return mod
end

local surround = safe_require('nvim-surround')
if surround then
  surround.setup()
end

local comment = safe_require('Comment')
if comment then
  comment.setup()
end

local autopairs = safe_require('nvim-autopairs')
if autopairs then
  autopairs.setup()
end

local which_key = safe_require('which-key')
if which_key then
  which_key.setup()
end

local trouble = safe_require('trouble')
if trouble then
  trouble.setup()
end

local conform = safe_require('conform')
if conform then
  conform.setup({
    formatters_by_ft = {
      go = { 'gofmt' },
      json = { 'jq' },
    },
  })
end

local smart_splits = safe_require('smart-splits')
if smart_splits then
  smart_splits.setup({})
end

local gitsigns = safe_require('gitsigns')
if gitsigns then
  gitsigns.setup()
end

local yazi = safe_require('yazi')
if yazi then
  yazi.setup({
    open_for_directories = true,
    floating_window_scaling_factor = 0.9,
  })
end

local lualine = safe_require('lualine')
if lualine then
  lualine.setup({ options = { theme = 'auto' } })
end

local bufferline = safe_require('bufferline')
if bufferline then
  bufferline.setup {}
end

-- Support both older and newer nvim-treesitter module names without showing a
-- startup warning when only one of the names exists.
local treesitter_ok, treesitter_configs = pcall(require, 'nvim-treesitter.configs')
if not treesitter_ok then
  treesitter_ok, treesitter_configs = pcall(require, 'nvim-treesitter.config')
end
if treesitter_configs then
  treesitter_configs.setup {
    ensure_installed = { "lua", "vim", "vimdoc", "javascript", "python", "typescript", "html", "css" },
    highlight = {
      enable = true,
    },
  }
else
  vim.notify('[nvim] nvim-treesitter is not installed. Run :PlugInstall to enable Treesitter syntax highlighting.')
end

-- Basic LSP setup (customize language servers as needed)
local server_list = { "lua_ls", "ts_ls", "pyright", "gopls", "jsonls", "yamlls", "marksman", "bashls" }
local cmp_capabilities = {}
local cmp_nvim_lsp = safe_require('cmp_nvim_lsp')
if cmp_nvim_lsp then
  cmp_capabilities = cmp_nvim_lsp.default_capabilities()
end

local mason = safe_require('mason')
if mason then
  mason.setup()
end

local mason_lspconfig = safe_require('mason-lspconfig')
if mason_lspconfig then
  mason_lspconfig.setup({
    ensure_installed = server_list,
  })
end

local function lsp_setup_with_legacy_fallback(server_name)
  local lspconfig = safe_require('lspconfig')
  if not lspconfig then
    return
  end
  local candidates = { server_name }
  if server_name == "ts_ls" then
    table.insert(candidates, "tsserver")
  elseif server_name == "tsserver" then
    table.insert(candidates, "ts_ls")
  end

  for _, name in ipairs(candidates) do
    local entry = lspconfig[name]
    if type(entry) == "table" and type(entry.setup) == "function" then
      entry.setup({
        capabilities = cmp_capabilities,
      })
      return
    end
  end
end

if vim.lsp and vim.lsp.config and vim.lsp.enable then
  for _, server_name in ipairs(server_list) do
    pcall(vim.lsp.config, server_name, {
      capabilities = cmp_capabilities,
    })
  end
  pcall(vim.lsp.enable, server_list)
elseif mason_lspconfig and mason_lspconfig.setup_handlers then
  mason_lspconfig.setup_handlers({
    function(server_name)
      lsp_setup_with_legacy_fallback(server_name)
    end,
  })
else
  for _, server_name in ipairs(server_list) do
    lsp_setup_with_legacy_fallback(server_name)
  end
end

-- Basic completion setup
local cmp = safe_require('cmp')
if cmp then
  local luasnip = safe_require('luasnip')
  cmp.setup({
    snippet = {
      expand = function(args)
        if luasnip then
          luasnip.lsp_expand(args.body)
        end
      end,
    },
    mapping = cmp.mapping.preset.insert({
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<CR>'] = cmp.mapping.confirm({ select = true }),
    }),
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'luasnip' },
    }, {
      { name = 'buffer' },
    })
  })
end
EOF

" ============================================================================
" ========================= VISUAL SETTINGS =================================
" ============================================================================
" Prefer Atom One family in both light/dark mode.
function! s:NvimIsDarkMode()
  if !has('macunix')
    return &background ==# 'dark'
  endif

  let l:pref = trim(system("defaults read -g AppleInterfaceStyle 2>/dev/null"))
  if v:shell_error == 0 && l:pref ==# 'Dark'
    return 1
  endif

  let l:dark_mode = trim(system("osascript -e 'tell application \"System Events\" to tell appearance preferences to return dark mode' 2>/dev/null"))
  if v:shell_error == 0
    return l:dark_mode ==# 'true'
  endif

  return &background ==# 'dark'
endfunction

function! s:ApplyNvimTheme()
  let l:is_dark_mode = s:NvimIsDarkMode()
  if l:is_dark_mode
    set background=dark
  else
    set background=light
  endif
  let g:one_allow_italics = 1

  try
    colorscheme one
    echom '[nvim] applied Atom One (' . (l:is_dark_mode ? 'dark' : 'light') . ')'
  catch /^Vim\%((\a\+)\)\=:E185/
    echom '[nvim] Atom One not installed yet; run :PlugInstall'
    colorscheme default
  endtry
endfunction

command! NvimThemeSync call s:ApplyNvimTheme()

augroup nvim_auto_theme
  autocmd!
  autocmd VimEnter * call s:ApplyNvimTheme()
  autocmd VimResume * call s:ApplyNvimTheme()
  autocmd FocusGained * call s:ApplyNvimTheme()
augroup END

" Enable highlighted yank
let g:highlightedyank_highlight_duration = 300

" ============================================================================
" ========================= SEARCH SETTINGS =================================
" ============================================================================
set hlsearch
set noincsearch
set ignorecase
set smartcase

" ============================================================================
" ========================= LEADER CONFIGURATION ============================
" ============================================================================
let mapleader = ","

" ============================================================================
" ========================= COMMANDS ========================================
" ============================================================================
command! Format lua require('conform').format({ lsp_fallback = true, async = false })

" ============================================================================
" ========================= KEY MAPPINGS ====================================
" ============================================================================

" ----- Navigation -----
" Better line movement (works with wrapped lines)
nnoremap j gj
nnoremap k gk
vnoremap j gj
vnoremap k gk
xnoremap j gj
xnoremap k gk

" Faster vertical movement
nnoremap J 5gj
nnoremap K 5gk
vnoremap J 5gj
vnoremap K 5gk
xnoremap J 5gj
xnoremap K 5gk

" Scrolling and centering
nnoremap t zt
nnoremap <leader><leader> zz
nnoremap <C-u> MHzz
nnoremap <C-d> MLzz
vnoremap <C-u> MHzz
vnoremap <C-d> MLzz
xnoremap <C-u> MHzz
xnoremap <C-d> MLzz

" Arrow keys for scrolling
nnoremap <Up> <C-y>
nnoremap <Down> <C-e>
vnoremap <Up> <C-y>
vnoremap <Down> <C-e>

" ----- Editing -----
" Removed s mapping since we're using it for EasyMotion
nnoremap <leader>d "_dd
nnoremap <leader>p "_dP
nnoremap <silent> <leader>l :nohl<CR>

" Zed-aligned tab/buffer switching
" Zed habit: Ctrl+S toggles last tab
nnoremap <silent> <C-s> :b#<CR>
inoremap <silent> <C-s> <Esc>:b#<CR>
vnoremap <silent> <C-s> <Esc>:b#<CR>

" Zed habit: F1..F7 jump to tab index, F10 jump last tab
nnoremap <silent> <F1> :silent! b1<CR>
nnoremap <silent> <F2> :silent! b2<CR>
nnoremap <silent> <F3> :silent! b3<CR>
nnoremap <silent> <F4> :silent! b4<CR>
nnoremap <silent> <F5> :silent! b5<CR>
nnoremap <silent> <F6> :silent! b6<CR>
nnoremap <silent> <F7> :silent! b7<CR>
nnoremap <silent> <F10> :b#<CR>
nnoremap <silent> ]b :bnext<CR>
nnoremap <silent> [b :bprevious<CR>
nnoremap <silent> ]w :wincmd w<CR>
nnoremap <silent> [w :wincmd W<CR>

" Fast accept for external-editor workflows (Codex Ctrl+G, etc.)
" Use Ctrl+Q to avoid conflict with Zed-style Ctrl+S switch habit.
nnoremap <silent> <C-q> :wq<CR>
inoremap <silent> <C-q> <Esc>:wq<CR>
vnoremap <silent> <C-q> <Esc>:wq<CR>

" ----- Search Mappings (Telescope) -----
nnoremap <silent> <C-p>      <cmd>Telescope find_files<cr>
nnoremap <silent> <leader>f  <cmd>Telescope find_files<cr>
nnoremap <silent> <leader>fp <cmd>Telescope find_files<cr>
nnoremap <silent> <leader>gf <cmd>Telescope git_files<cr>
nnoremap <silent> <leader>b  <cmd>Telescope buffers<cr>
nnoremap <silent> <leader>r  <cmd>Telescope live_grep<cr>
nnoremap <silent> <leader>c  <cmd>Telescope commands<cr>

" ----- Split Navigation -----
nnoremap <silent> <C-h> :lua require('smart-splits').move_cursor_left()<CR>
nnoremap <silent> <C-l> :lua require('smart-splits').move_cursor_right()<CR>
nnoremap <silent> <C-k> :lua require('smart-splits').move_cursor_up()<CR>
nnoremap <silent> <C-j> :lua require('smart-splits').move_cursor_down()<CR>

" ----- Daily Workflow Commands -----
function! s:CloseBufferNoLayout()
  let l:current = bufnr('%')
  let l:list = filter(range(1, bufnr('$')), 'buflisted(v:val)')

  if len(l:list) <= 1
    enew
    execute 'bdelete ' . l:current
    return
  endif

  bnext
  bdelete #
endfunction

command! LazyGit terminal lazygit
command! CloseBufferNoLayout call <SID>CloseBufferNoLayout()

nnoremap <silent> <leader>gg :LazyGit<CR>
nnoremap <silent> <leader>yy <cmd>Yazi<cr>
nnoremap <silent> <leader>yp :let @+=expand('%:p')<CR>:echo 'Copied: ' . expand('%:p')<CR>
nnoremap <silent> <leader>= :Format<CR>
nnoremap <silent> <leader>m  <cmd>Telescope marks<cr>
nnoremap <silent> <leader>h  <cmd>Telescope oldfiles<cr>
nnoremap <silent> <leader>/  <cmd>Telescope current_buffer_fuzzy_find<cr>
nnoremap <silent> <leader>x :CloseBufferNoLayout<CR>

" ----- Telescope Mappings -----
nnoremap <silent> <leader>tf <cmd>Telescope find_files<cr>
nnoremap <silent> <leader>tg <cmd>Telescope live_grep<cr>
nnoremap <silent> <leader>tb <cmd>Telescope buffers<cr>
nnoremap <silent> <leader>th <cmd>Telescope help_tags<cr>

" ----- Window Management -----
nnoremap <leader>w <C-w>
nnoremap <silent> <leader>vs <cmd>vsplit<cr>
nnoremap <silent> <leader>hs <cmd>split<cr>
" Zed-like split-right quick action
nnoremap <silent> <leader>sr <cmd>vsplit<cr>
nnoremap <silent> <leader>sb <cmd>split<cr>
nnoremap <silent> <leader>tt <cmd>botright split<bar>terminal<cr>

" ----- File Explorer (NERDTree) -----
nnoremap <silent> <leader>e <cmd>NERDTreeToggle<cr>
" Find current file in NERDTree
nnoremap <silent> <leader>nf <cmd>NERDTreeFind<cr>

" ----- Buffer Navigation -----
nnoremap <silent> <leader>bn <cmd>bnext<cr>
nnoremap <silent> <leader>bp <cmd>bprevious<cr>
nnoremap <silent> <leader>bd :CloseBufferNoLayout<CR>
nnoremap <silent> <M-l> <cmd>bnext<cr>
nnoremap <silent> <M-h> <cmd>bprevious<cr>

" ----- Markdown Helpers (Zed-style editing ergonomics) -----
augroup xj_markdown_keymaps
  autocmd!
  " Wrap visual selection with markdown markers
  autocmd FileType markdown xnoremap <silent> <buffer> <leader>mb c**<C-r>"**<Esc>
  autocmd FileType markdown xnoremap <silent> <buffer> <leader>mi c*<C-r>"*<Esc>
  autocmd FileType markdown xnoremap <silent> <buffer> <leader>mc c`<C-r>"`<Esc>
  " Prefix current line quickly
  autocmd FileType markdown nnoremap <silent> <buffer> <leader>ml I- <Space><Esc>
  autocmd FileType markdown nnoremap <silent> <buffer> <leader>mt I- [ ] <Esc>
augroup END

" ----- Filetype-specific save behavior (Zed-aligned, not global) -----
augroup xj_format_on_save
  autocmd!
  autocmd BufWritePre *.go,*.json lua require('conform').format({ lsp_fallback = true, async = false })
augroup END
