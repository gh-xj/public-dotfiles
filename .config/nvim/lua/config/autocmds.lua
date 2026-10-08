-- Loaded by LazyVim on VeryLazy, after its default autocmds.
local function augroup(name)
  return vim.api.nvim_create_augroup("xj_" .. name, { clear = true })
end
local autocmd = vim.api.nvim_create_autocmd

-- Prose buffers wrap but never spell-check.
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")
autocmd("FileType", {
  group = augroup("prose"),
  pattern = { "text", "markdown", "gitcommit" },
  callback = function()
    vim.opt_local.wrap = true
    vim.opt_local.linebreak = true
    vim.opt_local.breakindent = true
  end,
})

-- Markdown wrap/prefix helpers (Zed snippets parity).
autocmd("FileType", {
  group = augroup("markdown_keys"),
  pattern = "markdown",
  callback = function(ev)
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, desc = desc })
    end
    map("x", "<localleader>b", 'c**<C-r>"**<Esc>', "Bold")
    map("x", "<localleader>i", 'c*<C-r>"*<Esc>', "Italic")
    map("x", "<localleader>c", 'c`<C-r>"`<Esc>', "Inline code")
    map("n", "<localleader>l", "I- <Esc>", "List item")
    map("n", "<localleader>t", "I- [ ] <Esc>", "Task item")
  end,
})

-- Format on save only for Go and JSON, matching Zed.
autocmd("FileType", {
  group = augroup("format_on_save"),
  pattern = { "go", "json" },
  callback = function(ev)
    vim.b[ev.buf].autoformat = true
  end,
})

-- Zed-style autosave: write a modified file buffer one second after the last
-- normal-mode change, and immediately when leaving the buffer or Neovim.
local timers = {}
local function save(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local bo = vim.bo[buf]
  if not bo.modified or bo.buftype ~= "" or bo.readonly or not bo.modifiable
    or vim.api.nvim_buf_get_name(buf) == "" or vim.b[buf].autosave == false then
    return
  end
  -- Wait for InsertLeave instead of writing under an active insert.
  if buf == vim.api.nvim_get_current_buf() and vim.fn.mode():match("^[iR]") then return end
  vim.api.nvim_buf_call(buf, function() vim.cmd("silent! lockmarks update") end)
end
local autosave = augroup("autosave")
autocmd({ "InsertLeave", "TextChanged" }, {
  group = autosave,
  callback = function(ev)
    local timer = timers[ev.buf] or vim.uv.new_timer()
    timers[ev.buf] = timer
    timer:start(1000, 0, vim.schedule_wrap(function() save(ev.buf) end))
  end,
})
autocmd({ "BufLeave", "FocusLost", "VimLeavePre" }, {
  group = autosave,
  callback = function(ev) save(ev.buf) end,
})
autocmd("BufWipeout", {
  group = autosave,
  callback = function(ev)
    if timers[ev.buf] then
      timers[ev.buf]:close()
      timers[ev.buf] = nil
    end
  end,
})

-- Live reload: agents edit files in other tmux panes while this one stays
-- focused, so poll every second instead of waiting for FocusGained. Clean
-- buffers reload silently; a buffer with unsaved edits keeps them and warns.
autocmd("FileChangedShell", {
  group = augroup("reload"),
  callback = function(ev)
    if vim.v.fcs_reason == "deleted" or vim.bo[ev.buf].modified then
      vim.v.fcs_choice = ""
      vim.notify(("%s changed on disk (%s); :e! reloads, :w! keeps yours")
        :format(vim.fn.fnamemodify(ev.file, ":~:."), vim.v.fcs_reason), vim.log.levels.WARN)
    else
      vim.v.fcs_choice = "reload"
    end
  end,
})
vim.uv.new_timer():start(1000, 1000, vim.schedule_wrap(function()
  if vim.fn.getcmdwintype() == "" and not vim.fn.mode():match("^[cr!]") then
    vim.cmd("silent! checktime")
  end
end))

-- Theme follows the terminal: Nvim re-queries the background on Ghostty's
-- theme-change notification (DEC 2031) and 'background' flips here.
autocmd("OptionSet", {
  group = augroup("theme"),
  pattern = "background",
  callback = function()
    local want = vim.o.background == "light" and "onelight" or "onedark"
    if vim.g.colors_name ~= want then vim.cmd.colorscheme(want) end
  end,
})
