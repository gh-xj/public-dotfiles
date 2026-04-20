local M = {}

local directions = {
  left = { wincmd = "h", tmux = "-L" },
  down = { wincmd = "j", tmux = "-D" },
  up = { wincmd = "k", tmux = "-U" },
  right = { wincmd = "l", tmux = "-R" },
}

local function in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

local function at_edge(direction)
  local wincmd = directions[direction].wincmd
  return vim.fn.winnr(wincmd) == vim.fn.winnr()
end

local function move_tmux(direction)
  vim.fn.jobstart({ "tmux", "select-pane", directions[direction].tmux }, { detach = true })
end

function M.move(direction)
  if not at_edge(direction) then
    vim.cmd.wincmd(directions[direction].wincmd)
    return
  end

  if in_tmux() then
    move_tmux(direction)
  end
end

return M
