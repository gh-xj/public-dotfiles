-- Additions to LazyVim's markdown extra (render-markdown, preview, marksman, lint).
return {
  -- List continuation: <CR> on `- item` or `1. item` continues the list.
  {
    "dkarter/bullets.vim",
    ft = { "markdown", "text", "gitcommit" },
    init = function()
      vim.g.bullets_enabled_file_types = { "markdown", "text", "gitcommit" }
      vim.g.bullets_checkbox_markers = " x"
      -- Defaults minus <leader>x, which belongs to Trouble; checkbox is ,x.
      vim.g.bullets_set_mappings = 0
      vim.g.bullets_custom_mappings = {
        { "imap", "<cr>", "<Plug>(bullets-newline)" },
        { "inoremap", "<C-cr>", "<cr>" },
        { "nmap", "o", "<Plug>(bullets-newline)" },
        { "nmap", "gN", "<Plug>(bullets-renumber)" },
        { "vmap", "gN", "<Plug>(bullets-renumber)" },
        { "nmap", "<localleader>x", "<Plug>(bullets-toggle-checkbox)" },
        { "imap", "<C-t>", "<Plug>(bullets-demote)" },
        { "nmap", ">>", "<Plug>(bullets-demote)" },
        { "vmap", ">", "<Plug>(bullets-demote)" },
        { "imap", "<C-d>", "<Plug>(bullets-promote)" },
        { "nmap", "<<", "<Plug>(bullets-promote)" },
        { "vmap", "<", "<Plug>(bullets-promote)" },
      }
    end,
  },

  -- ,p saves the clipboard image under ./assets/ and links it (needs pngpaste).
  {
    "HakonHarnes/img-clip.nvim",
    ft = "markdown",
    opts = {
      default = {
        dir_path = "assets",
        relative_to_current_file = true,
        prompt_for_file_name = false,
        file_name = "%Y%m%d-%H%M%S",
      },
    },
    keys = {
      { "<localleader>p", function() require("img-clip").paste_image() end, ft = "markdown", desc = "Paste clipboard image" },
    },
  },
}
