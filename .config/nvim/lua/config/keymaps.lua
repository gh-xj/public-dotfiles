local map = vim.keymap.set

-- ===== Navigation =====
-- Better line movement (works with wrapped lines)
map({ "n", "v", "x" }, "j", "gj")
map({ "n", "v", "x" }, "k", "gk")

-- Faster vertical movement
map({ "n", "v", "x" }, "J", "5gj")
map({ "n", "v", "x" }, "K", "5gk")

-- Scrolling / centering helpers
map("n", "t", "zt")
map("n", "<leader><leader>", "zz")
map({ "n", "v", "x" }, "<C-d>", "<C-d>zz")
map({ "n", "v", "x" }, "<C-u>", "<C-u>zz")

-- Arrow keys for scrolling + tab switching
map({ "n", "v" }, "<Up>", "<C-y>")
map({ "n", "v" }, "<Down>", "<C-e>")
map("n", "<Left>", ":BufferLineCyclePrev<CR>", { silent = true, desc = "Previous buffer" })
map("n", "<Right>", ":BufferLineCycleNext<CR>", { silent = true, desc = "Next buffer" })

-- ===== Editing =====
map("n", "<leader>d", '"_dd')
map("n", "<leader>p", '"_dP')
map("n", "<leader>l", ":nohl<CR>", { silent = true })

-- Open URL under cursor in browser. Overrides the built-in gx so we can skip
-- weird leading characters (fullwidth punctuation, brackets) that <cfile>
-- sometimes grabs and macOS `open` refuses.
map({ "n", "x" }, "gx", function()
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local best
  local start = 1
  while true do
    local s, e, match = line:find("(https?://[%w%-%._~:/?#%[%]@!$&'()*+,;=%%]+)", start)
    if not s then break end
    match = match:gsub("[%.,%);%]]+$", "")
    if col >= s and col <= e then
      best = match
      break
    end
    if not best then best = match end
    start = e + 1
  end
  if best then
    vim.ui.open(best)
  else
    vim.notify("gx: no URL on this line", vim.log.levels.WARN)
  end
end, { silent = true, desc = "Open URL on current line" })

-- Diagnostic hops (Zed-aligned ]d / [d)
map("n", "]d", function() vim.diagnostic.jump({ count = 1, float = true }) end,
  { silent = true, desc = "Next diagnostic" })
map("n", "[d", function() vim.diagnostic.jump({ count = -1, float = true }) end,
  { silent = true, desc = "Prev diagnostic" })

-- ===== Buffer index jumps (F1..F9 → Nth bufferline buffer, or create new; F10 → last buffer) =====
-- Only bound in normal mode; terminal buffers (yazi.nvim float, :term) keep
-- their own F-key handling so yazi can switch its own tabs.
local function go_to_buffer_or_new(n)
  local ok, bufferline = pcall(require, "bufferline")
  if not ok then
    vim.cmd("enew")
    return
  end
  local elements = bufferline.get_elements().elements
  if n <= #elements then
    vim.cmd("BufferLineGoToBuffer " .. n)
  else
    vim.cmd("enew")
  end
end

for i = 1, 9 do
  map("n", "<F" .. i .. ">", function() go_to_buffer_or_new(i) end, { silent = true })
end
map("n", "<F10>", ":b#<CR>", { silent = true })

map("n", "]b", ":bnext<CR>", { silent = true })
map("n", "[b", ":bprevious<CR>", { silent = true })
map("n", "]w", ":wincmd w<CR>", { silent = true })
map("n", "[w", ":wincmd W<CR>", { silent = true })

-- Fast accept for external-editor workflows (Codex Ctrl+G, etc.)
map("n", "<C-q>", ":wq<CR>", { silent = true })
map("i", "<C-q>", "<Esc>:wq<CR>", { silent = true })
map("v", "<C-q>", "<Esc>:wq<CR>", { silent = true })

-- ===== Telescope =====
map("n", "<C-p>", "<cmd>Telescope find_files<cr>", { silent = true })
map("n", "<leader>f", "<cmd>Telescope find_files<cr>", { silent = true })
map("n", "<leader>fp", "<cmd>Telescope find_files<cr>", { silent = true })
map("n", "<leader>gf", "<cmd>Telescope git_files<cr>", { silent = true })
map("n", "<leader>b", "<cmd>Telescope buffers<cr>", { silent = true })
map("n", "<leader>r", "<cmd>Telescope live_grep<cr>", { silent = true })
map("n", "<leader>c", "<cmd>Telescope commands<cr>", { silent = true })
map("n", "<leader>m", "<cmd>Telescope marks<cr>", { silent = true })
map("n", "<leader>h", "<cmd>Telescope oldfiles<cr>", { silent = true })
map("n", "<leader>/", "<cmd>Telescope current_buffer_fuzzy_find<cr>", { silent = true })

-- Zed-aligned symbol search (Telescope-backed)
map("n", "gs", "<cmd>Telescope lsp_document_symbols<cr>", { silent = true, desc = "Symbols in file" })
map("n", "gS", "<cmd>Telescope lsp_workspace_symbols<cr>", { silent = true, desc = "Symbols in project" })
map("n", "<leader>o", function() require("aerial").toggle({ focus = true }) end,
  { silent = true, desc = "Toggle outline panel" })

map("n", "<leader>tf", "<cmd>Telescope find_files<cr>", { silent = true })
map("n", "<leader>tg", "<cmd>Telescope live_grep<cr>", { silent = true })
map("n", "<leader>tb", "<cmd>Telescope buffers<cr>", { silent = true })
map("n", "<leader>tk", "<cmd>Telescope keymaps<cr>", { silent = true })
map("n", "<leader>th", "<cmd>Telescope help_tags<cr>", { silent = true })

-- ===== Split Navigation (local nvim/tmux bridge, loaded on demand) =====
map("n", "<C-h>", function() require("config.tmux_navigation").move("left") end,
  { silent = true, desc = "Move to left split or tmux pane" })
map("n", "<C-l>", function() require("config.tmux_navigation").move("right") end,
  { silent = true, desc = "Move to right split or tmux pane" })
map("n", "<C-k>", function() require("config.tmux_navigation").move("up") end,
  { silent = true, desc = "Move to upper split or tmux pane" })
map("n", "<C-j>", function() require("config.tmux_navigation").move("down") end,
  { silent = true, desc = "Move to lower split or tmux pane" })

-- ===== Daily workflow =====
local function close_buffer_no_layout()
  local current = vim.fn.bufnr("%")
  local listed = vim.tbl_filter(function(b) return vim.fn.buflisted(b) == 1 end, vim.fn.range(1, vim.fn.bufnr("$")))
  if #listed <= 1 then
    vim.cmd("enew")
    vim.cmd("bdelete " .. current)
    return
  end
  vim.cmd("bnext")
  vim.cmd("bdelete #")
end

vim.api.nvim_create_user_command("CloseBufferNoLayout", close_buffer_no_layout, {})
vim.api.nvim_create_user_command("LazyGit", "terminal lazygit", {})
vim.api.nvim_create_user_command("Format", function()
  require("conform").format({ lsp_fallback = true, async = false })
end, {})

map("n", "<leader>gg", ":LazyGit<CR>", { silent = true })
map("n", "<C-e>", "<cmd>Yazi<cr>", { silent = true, desc = "Open yazi" })
map("n", "<leader>e", "<cmd>Yazi<cr>", { silent = true, desc = "Open yazi" })
map("n", "<leader>yp", ":let @+=expand('%:p')<CR>:echo 'Copied: ' . expand('%:p')<CR>", { silent = true })
map("n", "<leader>=", ":Format<CR>", { silent = true })
map("n", "<leader>sv", ":source ~/.config/nvim/init.lua<CR>", { silent = true })
map("n", "<leader>x", ":CloseBufferNoLayout<CR>", { silent = true })

-- ===== Window management =====
map("n", "<leader>w", "<C-w>")
map("n", "<leader>vs", "<cmd>vsplit<cr>", { silent = true })
map("n", "<leader>hs", "<cmd>split<cr>", { silent = true })
map("n", "<leader>sr", "<cmd>vsplit<cr>", { silent = true })
map("n", "<leader>sb", "<cmd>split<cr>", { silent = true })
map("n", "<leader>tt", "<cmd>botright split<bar>terminal<cr>", { silent = true })

-- ===== Buffer navigation =====
map("n", "<leader>bn", "<cmd>bnext<cr>", { silent = true })
map("n", "<leader>bp", "<cmd>bprevious<cr>", { silent = true })
map("n", "<leader>bd", ":CloseBufferNoLayout<CR>", { silent = true })
map("n", "<M-l>", "<cmd>bnext<cr>", { silent = true })
map("n", "<M-h>", "<cmd>bprevious<cr>", { silent = true })
