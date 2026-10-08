-- Loaded by LazyVim on VeryLazy, after its default keymaps.
local map = vim.keymap.set

-- tmux owns Ctrl-h/j/k/l (docs/ghostty-tmux.md); Neovim splits use Ctrl-w h/j/k/l.
for _, lhs in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>" }) do
  pcall(vim.keymap.del, "n", lhs)
end

-- ===== Movement (shared with Zed, see docs/zed.md) =====
map({ "n", "x" }, "J", "5gj", { desc = "Down 5 display lines" })
map({ "n", "x" }, "K", "5gk", { desc = "Up 5 display lines" })
map("n", "t", "zt", { desc = "Scroll cursor line to top" })
map({ "n", "x" }, "<Up>", "<C-y>", { desc = "Scroll up one line" })
map({ "n", "x" }, "<Down>", "<C-e>", { desc = "Scroll down one line" })

-- ===== Buffers =====
map("n", "<Left>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
map("n", "<Right>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
map("n", "<M-h>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Prev Buffer" })
map("n", "<M-l>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })

-- F1..F9 jump to the Nth bufferline buffer, or open an empty one; F10 is the
-- alternate buffer. Normal mode only, so yazi's terminal keeps its F-keys.
for i = 1, 9 do
  map("n", "<F" .. i .. ">", function()
    if i <= #require("bufferline").get_elements().elements then
      vim.cmd("BufferLineGoToBuffer " .. i)
    else
      vim.cmd.enew()
    end
  end, { desc = "Buffer " .. i .. " (or new)" })
end
map("n", "<F10>", "<cmd>b#<cr>", { desc = "Alternate buffer" })

map("n", "]w", "<cmd>wincmd w<cr>", { desc = "Next window" })
map("n", "[w", "<cmd>wincmd W<cr>", { desc = "Previous window" })

-- ===== Pickers and symbols =====
map("n", "<C-p>", function() Snacks.picker.files() end, { desc = "Find Files" })
map("n", "gs", function() Snacks.picker.lsp_symbols() end, { desc = "Symbols in file" })
map("n", "gS", function() Snacks.picker.lsp_workspace_symbols() end, { desc = "Symbols in project" })

-- Fast accept for external-editor workflows (Codex/Claude Ctrl-G).
map({ "n", "i", "x" }, "<C-q>", "<cmd>wq<cr>", { desc = "Save and quit" })

-- Open the URL on the current line. Unlike the built-in gx this skips leading
-- fullwidth punctuation and brackets that <cfile> grabs and `open` rejects.
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
end, { desc = "Open URL on current line" })
