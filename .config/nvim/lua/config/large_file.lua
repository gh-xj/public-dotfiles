local M = {}

local uv = vim.uv or vim.loop

M.max_markdown_bytes = 512 * 1024
M.max_markdown_lines = 5000

function M.buf_size(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return 0
  end

  local stat = uv.fs_stat(name)
  if not stat then
    return 0
  end

  return stat.size or 0
end

function M.is_large_markdown(buf)
  if vim.api.nvim_buf_line_count(buf) > M.max_markdown_lines then
    return true
  end

  return M.buf_size(buf) > M.max_markdown_bytes
end

function M.max_markdown_megabytes()
  return M.max_markdown_bytes / (1024 * 1024)
end

return M
