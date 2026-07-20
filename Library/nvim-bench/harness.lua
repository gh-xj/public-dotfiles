local uv = vim.uv or vim.loop
local started_at = uv.hrtime()
local output = vim.env.NVIM_BENCH_OUTPUT
local probe = vim.env.NVIM_BENCH_PROBE or "vim_enter"
local expected_client = vim.env.NVIM_BENCH_EXPECTED_CLIENT or ""
local timeout_ms = tonumber(vim.env.NVIM_BENCH_TIMEOUT_MS) or 5000
local finished = false

local function loaded_plugins()
  local ok, config = pcall(require, "lazy.core.config")
  if not ok then
    return {}
  end

  local names = {}
  for name, plugin in pairs(config.plugins) do
    if plugin._.loaded then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

local function clients()
  local result = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    table.insert(result, {
      name = client.name,
      initialized = client.initialized == true,
    })
  end
  table.sort(result, function(a, b) return a.name < b.name end)
  return result
end

local function finish(status, message)
  if finished then
    return
  end
  finished = true

  local payload = {
    schema_version = 1,
    probe = probe,
    expected_client = expected_client ~= "" and expected_client or nil,
    status = status,
    elapsed_ms = (uv.hrtime() - started_at) / 1e6,
    loaded_plugins = loaded_plugins(),
    clients = clients(),
  }
  if message then
    payload.error = message
  end

  local encoded = vim.json.encode(payload)
  vim.fn.writefile({ encoded }, output, "a")
  vim.schedule(function()
    if status == "passed" then
      vim.cmd("qa!")
    else
      vim.cmd("cquit 1")
    end
  end)
end

local function wait_for_lsp()
  local elapsed_ms = (uv.hrtime() - started_at) / 1e6
  local active = clients()
  for _, client in ipairs(active) do
    if client.name == expected_client and client.initialized then
      finish("passed")
      return
    end
  end
  if elapsed_ms >= timeout_ms then
    finish("failed", string.format(
      "LSP client %q was not initialized after %d ms",
      expected_client,
      timeout_ms
    ))
    return
  end
  vim.defer_fn(wait_for_lsp, 10)
end

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    if probe == "vim_enter" then
      -- Yield once so later VimEnter handlers (theme sync, lazy events, UI
      -- setup) complete before the ready timestamp and process exit.
      vim.schedule(function() finish("passed") end)
    elseif probe == "lsp_ready" then
      wait_for_lsp()
    else
      finish("failed", "unsupported probe: " .. probe)
    end
  end,
})
