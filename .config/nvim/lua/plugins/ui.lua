return {
  -- Zed-style breadcrumbs: file path and the enclosing symbols in each window's winbar.
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local symbols = require("trouble").statusline({
        mode = "symbols",
        groups = {},
        title = false,
        filter = { range = true },
        format = "{kind_icon}{symbol.name:Normal}",
        hl_group = "lualine_c_normal",
      })
      local path = LazyVim.lualine.pretty_path()
      opts.winbar = {
        lualine_c = {
          path,
          { symbols.get, cond = symbols.has },
        },
      }
      opts.inactive_winbar = { lualine_c = { path } }
      opts.options.disabled_filetypes.winbar = {
        "snacks_dashboard", "snacks_layout_box", "snacks_picker_list", "trouble", "lazy", "mason",
      }
    end,
  },
}
