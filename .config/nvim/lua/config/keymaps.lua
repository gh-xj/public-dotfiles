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

-- ===== Picker (Snacks) =====
map("n", "<C-p>",      function() Snacks.picker.files() end,                  { silent = true, desc = "Find files" })
map("n", "<leader>f",  function() Snacks.picker.files() end,                  { silent = true, desc = "Find files" })
map("n", "<leader>fp", function() Snacks.picker.files() end,                  { silent = true, desc = "Find files" })
map("n", "<leader>gf", function() Snacks.picker.git_files() end,              { silent = true, desc = "Git files" })
map("n", "<leader>b",  function() Snacks.picker.buffers() end,                { silent = true, desc = "Buffers" })
map("n", "<leader>r",  function() Snacks.picker.grep() end,                   { silent = true, desc = "Live grep" })
map("n", "<leader>c",  function() Snacks.picker.commands() end,               { silent = true, desc = "Commands" })
map("n", "<leader>m",  function() Snacks.picker.marks() end,                  { silent = true, desc = "Marks" })
map("n", "<leader>h",  function() Snacks.picker.recent() end,                 { silent = true, desc = "Recent files" })
map("n", "<leader>/",  function() Snacks.picker.lines() end,                  { silent = true, desc = "Lines in buffer" })

-- Zed-aligned symbol search
map("n", "gs", function() Snacks.picker.lsp_symbols() end,
  { silent = true, desc = "Symbols in file" })
map("n", "gS", function() Snacks.picker.lsp_workspace_symbols() end,
  { silent = true, desc = "Symbols in project" })
map("n", "<leader>o", "<cmd>AerialToggle<cr>",
  { silent = true, desc = "Toggle outline panel" })

map("n", "<leader>tf", function() Snacks.picker.files() end,    { silent = true, desc = "Find files" })
map("n", "<leader>tg", function() Snacks.picker.grep() end,     { silent = true, desc = "Live grep" })
map("n", "<leader>tb", function() Snacks.picker.buffers() end,  { silent = true, desc = "Buffers" })
map("n", "<leader>tk", function() Snacks.picker.keymaps() end,  { silent = true, desc = "Keymaps" })
map("n", "<leader>th", function() Snacks.picker.help() end,     { silent = true, desc = "Help tags" })
map("n", "<leader>?",  function() Snacks.picker.keymaps() end,  { silent = true, desc = "Search keymaps" })

-- ===== Daily workflow =====
vim.api.nvim_create_user_command("Format", function()
  require("lazy").load({ plugins = { "conform.nvim" } })
  require("conform").format({ lsp_fallback = true, async = false })
end, {})

map("n", "<leader>gg", function() Snacks.lazygit() end, { silent = true, desc = "Lazygit" })
map("n", "<C-e>", "<cmd>Yazi<cr>", { silent = true, desc = "Open yazi" })
map("n", "<leader>e", "<cmd>Yazi<cr>", { silent = true, desc = "Open yazi" })
map("n", "<leader>yp", ":let @+=expand('%:p')<CR>:echo 'Copied: ' . expand('%:p')<CR>", { silent = true })
map("n", "<leader>=", ":Format<CR>", { silent = true })
map("n", "<leader>sv", ":source ~/.config/nvim/init.lua<CR>", { silent = true })
map("n", "<leader>x", function() Snacks.bufdelete() end, { silent = true, desc = "Close buffer" })

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
map("n", "<leader>bd", function() Snacks.bufdelete() end, { silent = true, desc = "Close buffer" })
map("n", "<M-l>", "<cmd>bnext<cr>", { silent = true })
map("n", "<M-h>", "<cmd>bprevious<cr>", { silent = true })
