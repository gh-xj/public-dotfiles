-- Unified palette: search `:` commands and all keymaps in one picker. For
-- each command, the keymaps that invoke it are shown inline (right of the
-- command name), VSCode-style.
--
-- LIMIT: Vim's built-in normal-mode keys (`u` for undo, `dd`, `yy`, motions,
-- etc.) are hardcoded in Vim's core and do NOT appear in
-- `nvim_get_keymap()`. Searching "undo" finds `:undo` (ex command) but no
-- `u` next to it. For built-ins use `:help <name>` or <leader>th.
--
-- Triggered by <leader>P.

local M = {}

local MODES = { "n", "v", "x", "i", "o", "t", "s" }

local function collect_keymaps()
  local maps = {}
  for _, mode in ipairs(MODES) do
    for _, km in ipairs(vim.api.nvim_get_keymap(mode)) do
      table.insert(maps, vim.tbl_extend("force", km, { _mode = mode }))
    end
    for _, km in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
      table.insert(maps, vim.tbl_extend("force", km, { _mode = mode }))
    end
  end
  return maps
end

local function build_cmd_to_keys(maps)
  local cmd_to_keys = {}
  for _, km in ipairs(maps) do
    local rhs = km.rhs or ""
    local function add(cmd)
      cmd_to_keys[cmd] = cmd_to_keys[cmd] or {}
      table.insert(cmd_to_keys[cmd], km._mode .. " " .. km.lhs)
    end
    for cmd in rhs:gmatch("[<:][cC]md>:?(%a[%w_]+)") do add(cmd) end
    for cmd in rhs:gmatch("^:(%a[%w_]+)") do add(cmd) end
  end
  return cmd_to_keys
end

local function build_items()
  local maps = collect_keymaps()
  local cmd_to_keys = build_cmd_to_keys(maps)
  local items = {}

  for _, cmd_tbl in ipairs({ vim.api.nvim_get_commands({}), vim.api.nvim_buf_get_commands(0, {}) }) do
    for name, _ in pairs(cmd_tbl) do
      local keys = cmd_to_keys[name]
      local key_label = keys and ("  [" .. table.concat(keys, " | ") .. "]") or ""
      table.insert(items, {
        text = ":" .. name .. key_label,
        _kind = "cmd",
        _cmd = name,
      })
    end
  end

  for _, km in ipairs(maps) do
    local rhs_label = km.desc or km.rhs or (km.callback and "<lua callback>") or ""
    table.insert(items, {
      text = string.format("%s  %-22s → %s", km._mode, km.lhs, rhs_label:sub(1, 80)),
      _kind = "key",
      _mode = km._mode,
      _lhs = km.lhs,
    })
  end

  return items
end

function M.open()
  Snacks.picker.pick({
    source = "palette",
    title = "Palette (commands + keymaps)",
    items = build_items(),
    preview = "none",
    format = function(item) return { { item.text, "Normal" } } end,
    confirm = function(picker, item)
      picker:close()
      if item._kind == "cmd" then
        vim.schedule(function()
          local ok, err = pcall(vim.cmd, item._cmd)
          if not ok then vim.notify(err, vim.log.levels.ERROR) end
        end)
      elseif item._kind == "key" then
        vim.schedule(function()
          local feed = vim.api.nvim_replace_termcodes(item._lhs, true, false, true)
          vim.api.nvim_feedkeys(feed, item._mode, false)
        end)
      end
    end,
  })
end

vim.keymap.set("n", "<leader>P", M.open, { desc = "Palette: commands + keymaps" })

return M
