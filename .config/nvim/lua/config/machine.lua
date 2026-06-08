local machine_specific = vim.fs.joinpath(vim.fn.stdpath("state"), "machine-local.vim")
local machine_default = vim.fs.joinpath(vim.fn.stdpath("config"), "_machine_local.example.vim")

if vim.fn.filereadable(machine_specific) == 0 and vim.fn.filereadable(machine_default) == 1 then
  vim.fn.mkdir(vim.fn.fnamemodify(machine_specific, ":h"), "p")
  vim.fn.writefile(vim.fn.readfile(machine_default), machine_specific)
end

if vim.fn.filereadable(machine_specific) == 1 then
  vim.cmd("source " .. vim.fn.fnameescape(machine_specific))
end

vim.api.nvim_create_user_command("NvimMachineReload", function()
  if vim.fn.filereadable(machine_specific) == 1 then
    vim.cmd("source " .. vim.fn.fnameescape(machine_specific))
    vim.notify("Reloaded machine-specific nvim config.")
  else
    vim.notify("No machine-local nvim config found: " .. machine_specific, vim.log.levels.WARN)
  end
end, {})
