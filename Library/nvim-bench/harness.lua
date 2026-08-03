local uv = vim.uv or vim.loop
local started_at = uv.hrtime()
local output = vim.env.NVIM_BENCH_OUTPUT
local probe = vim.env.NVIM_BENCH_PROBE or "vim_enter"
local expected_client = vim.env.NVIM_BENCH_EXPECTED_CLIENT or ""
local client_scope = vim.env.NVIM_BENCH_CLIENT_SCOPE or ""
local expected_namespace = vim.env.NVIM_BENCH_EXPECTED_NAMESPACE or ""
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
  local opts = client_scope == "all" and {} or { bufnr = 0 }
  for _, client in ipairs(vim.lsp.get_clients(opts)) do
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
    schema_version = 2,
    probe = probe,
    expected_client = expected_client ~= "" and expected_client or nil,
    client_scope = probe == "lsp_ready" and (client_scope ~= "" and client_scope or "buffer") or nil,
    expected_namespace = expected_namespace ~= "" and expected_namespace or nil,
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

local function timed_out(message)
  local elapsed_ms = (uv.hrtime() - started_at) / 1e6
  if elapsed_ms < timeout_ms then
    return false
  end
  finish("failed", message)
  return true
end

local function wait_for_lsp()
  local active = clients()
  for _, client in ipairs(active) do
    if client.name == expected_client and client.initialized then
      finish("passed")
      return
    end
  end
  if timed_out(string.format(
    "LSP client %q was not initialized after %d ms",
    expected_client,
    timeout_ms
  )) then
    return
  end
  vim.defer_fn(wait_for_lsp, 10)
end

local function wait_for_render()
  local namespace = vim.api.nvim_get_namespaces()[expected_namespace]
  if namespace then
    local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, 0, namespace, 0, -1, {})
    if ok and #marks > 0 then
      finish("passed")
      return
    end
  end
  if timed_out(string.format(
    "namespace %q had no extmarks after %d ms",
    expected_namespace,
    timeout_ms
  )) then
    return
  end
  vim.defer_fn(wait_for_render, 10)
end

local function wait_for_completion()
  local line = vim.api.nvim_buf_line_count(0)
  local text = vim.api.nvim_buf_get_lines(0, line - 1, line, false)[1] or ""
  vim.api.nvim_win_set_cursor(0, { line, #text })
  vim.api.nvim_exec_autocmds("InsertEnter", { buffer = 0, modeline = false })

  local cmp
  local function wait_for_menu()
    if cmp.is_menu_visible() then
      finish("passed")
      return
    end
    if timed_out(string.format("completion menu was not ready after %d ms", timeout_ms)) then
      return
    end
    cmp.show({ providers = { "buffer" } })
    vim.defer_fn(wait_for_menu, 20)
  end

  vim.defer_fn(function()
    local ok
    ok, cmp = pcall(require, "blink.cmp")
    if not ok then
      finish("failed", "blink.cmp could not be loaded: " .. tostring(cmp))
      return
    end
    wait_for_menu()
  end, 10)
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
    elseif probe == "render_ready" then
      wait_for_render()
    elseif probe == "completion_ready" then
      vim.schedule(wait_for_completion)
    else
      finish("failed", "unsupported probe: " .. probe)
    end
  end,
})
