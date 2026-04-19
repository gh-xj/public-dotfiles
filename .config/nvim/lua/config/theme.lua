local function is_dark_mode()
  if vim.fn.has("macunix") == 0 then
    return vim.o.background == "dark"
  end

  local pref = vim.fn.trim(vim.fn.system("defaults read -g AppleInterfaceStyle 2>/dev/null"))
  if vim.v.shell_error == 0 and pref == "Dark" then
    return true
  end

  local dark = vim.fn.trim(vim.fn.system(
    "osascript -e 'tell application \"System Events\" to tell appearance preferences to return dark mode' 2>/dev/null"
  ))
  if vim.v.shell_error == 0 then
    return dark == "true"
  end

  return vim.o.background == "dark"
end

local function apply_theme()
  local dark = is_dark_mode()
  vim.o.background = dark and "dark" or "light"
  vim.g.one_allow_italics = 1

  local ok = pcall(vim.cmd.colorscheme, "one")
  if ok then
    vim.notify("[nvim] applied Atom One (" .. (dark and "dark" or "light") .. ")")
  else
    vim.notify("[nvim] Atom One not installed yet; run :Lazy install", vim.log.levels.WARN)
    pcall(vim.cmd.colorscheme, "default")
  end
end

vim.api.nvim_create_user_command("NvimThemeSync", apply_theme, {})

local group = vim.api.nvim_create_augroup("nvim_auto_theme", { clear = true })
vim.api.nvim_create_autocmd({ "VimEnter", "VimResume", "FocusGained" }, {
  group = group,
  callback = apply_theme,
})
