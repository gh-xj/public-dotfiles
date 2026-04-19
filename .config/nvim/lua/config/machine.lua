local machine_specific = vim.fn.expand("~/.config/nvim/_machine_specific.vim")
local machine_default = vim.fn.expand("~/.config/nvim/_machine_specific_default.vim")

if vim.fn.filereadable(machine_specific) == 0 and vim.fn.filereadable(machine_default) == 1 then
  vim.fn.system({ "cp", machine_default, machine_specific })
end

if vim.fn.filereadable(machine_specific) == 1 then
  vim.cmd("source " .. vim.fn.fnameescape(machine_specific))
end

vim.api.nvim_create_user_command("NvimMachineReload", function()
  if vim.fn.filereadable(machine_specific) == 1 then
    vim.cmd("source " .. vim.fn.fnameescape(machine_specific))
    vim.notify("Reloaded machine-specific nvim config.")
  else
    vim.notify("No machine-specific config found: " .. machine_specific, vim.log.levels.WARN)
  end
end, {})
