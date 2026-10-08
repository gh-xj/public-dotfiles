-- Additions to LazyVim's markdown extra (render-markdown, preview, marksman).
return {
  -- No markdownlint: style rules (MD012 etc.) fire mid-edit and read as noise.
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters_by_ft.markdown = {}
    end,
  },

  -- Same rendered view in every mode, so entering insert never flips the buffer
  -- to raw markdown. Without anti-conceal the cursor line stays rendered too;
  -- concealcursor "nc" still reveals ** / ` markers on the line while inserting.
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      render_modes = true,
      anti_conceal = { enabled = false },
      win_options = { concealcursor = { rendered = "nc" } },
    },
  },

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
