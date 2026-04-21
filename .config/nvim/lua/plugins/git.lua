local function should_enable_gitsigns(buf)
  local large_file = require("config.large_file")
  if vim.bo[buf].buftype ~= "" or large_file.is_large_buffer(buf) then
    return false
  end

  local name = vim.api.nvim_buf_get_name(buf)
  if name == "" then
    return false
  end

  local dir = vim.fs.dirname(name)
  if not dir or dir == "" then
    return false
  end

  return #vim.fs.find(".git", { path = dir, upward = true, limit = 1 }) > 0
end

return {
  {
    "lewis6991/gitsigns.nvim",
    cmd = { "Gitsigns" },
    init = function()
      local group = vim.api.nvim_create_augroup("xj_gitsigns_lazy", { clear = true })
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
        group = group,
        callback = function(ev)
          if not should_enable_gitsigns(ev.buf) then
            return
          end

          require("lazy").load({ plugins = { "gitsigns.nvim" } })
        end,
      })
    end,
    opts = {
      max_file_length = require("config.large_file").max_lines,
      on_attach = function(bufnr)
        local gs = require("gitsigns")
        local function map(mode, lhs, rhs, desc)
          vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
        end

        -- Zed-aligned hunk navigation
        map("n", "]c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "]c", bang = true })
          else
            gs.nav_hunk("next")
          end
        end, "Next git hunk")

        map("n", "[c", function()
          if vim.wo.diff then
            vim.cmd.normal({ "[c", bang = true })
          else
            gs.nav_hunk("prev")
          end
        end, "Prev git hunk")

      end,
    },
  },
}
