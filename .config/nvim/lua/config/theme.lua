local function is_dark_mode()
  if vim.fn.has("macunix") == 0 then
    return vim.o.background == "dark"
  end

  local pref = vim.fn.trim(vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null"))
  return vim.v.shell_error == 0 and pref == "Dark"
end

-- Atom One does not ship Headline1..6 / CodeBlock / Dash / Quote, but
-- headlines.nvim looks them up by name. Define them per mode so each
-- markdown heading level gets its own tinted background block.
local function apply_markdown_styles(dark)
  local groups
  if dark then
    groups = {
      Headline1 = { bg = "#3e2a30", bold = true },
      Headline2 = { bg = "#3e372a", bold = true },
      Headline3 = { bg = "#3e3c2a", bold = true },
      Headline4 = { bg = "#2a3e2d", bold = true },
      Headline5 = { bg = "#2a363e", bold = true },
      Headline6 = { bg = "#332a3e", bold = true },
      CodeBlock = { bg = "#21242b" },
      Dash      = { fg = "#5c6370", bold = true },
      Quote     = { fg = "#828997" },
    }
  else
    groups = {
      Headline1 = { bg = "#fadddd", bold = true },
      Headline2 = { bg = "#faead4", bold = true },
      Headline3 = { bg = "#faf2d4", bold = true },
      Headline4 = { bg = "#e0f5e0", bold = true },
      Headline5 = { bg = "#d8eaf5", bold = true },
      Headline6 = { bg = "#ecd8f5", bold = true },
      CodeBlock = { bg = "#f0f0f0" },
      Dash      = { fg = "#a0a1a7", bold = true },
      Quote     = { fg = "#a0a1a7" },
    }
  end
  for name, val in pairs(groups) do
    vim.api.nvim_set_hl(0, name, val)
  end
end

local function apply_theme(opts)
  opts = opts or {}
  local dark = is_dark_mode()
  local background = dark and "dark" or "light"

  if not opts.force and vim.g.xj_nvim_background == background and vim.g.colors_name == "one" then
    return
  end

  vim.o.background = background
  vim.g.one_allow_italics = 1

  local ok = pcall(vim.cmd.colorscheme, "one")
  if ok then
    apply_markdown_styles(dark)
    vim.g.xj_nvim_background = background
    if not opts.silent then
      vim.notify("[nvim] applied Atom One (" .. background .. ")")
    end
  else
    if not opts.silent then
      vim.notify("[nvim] Atom One not installed yet; run :Lazy install", vim.log.levels.WARN)
    end
    pcall(vim.cmd.colorscheme, "default")
  end
end

vim.api.nvim_create_user_command("NvimThemeSync", function()
  apply_theme({ force = true })
end, {})

local group = vim.api.nvim_create_augroup("nvim_auto_theme", { clear = true })
vim.api.nvim_create_autocmd({ "VimEnter", "VimResume" }, {
  group = group,
  callback = function()
    apply_theme({ silent = true })
  end,
})
