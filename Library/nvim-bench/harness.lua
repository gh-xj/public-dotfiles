local uv = vim.uv or vim.loop
local started_at = uv.hrtime()

-- Sleep guard clocks (the Go side documents the rationale in samples.go).
-- uv.hrtime() keeps counting through system sleep on macOS, so a sample that
-- spans a suspend cannot be recognised from hrtime alone. CLOCK_UPTIME_RAW (8)
-- stops during sleep; wall minus awake elapsed is the time the host slept
-- inside this sample. Both readings are optional: when unavailable they are
-- simply omitted from the payload.
local awake_clock
do
  local ok, ffi = pcall(require, "ffi")
  if ok and jit and jit.os == "OSX" then
    pcall(ffi.cdef, "uint64_t clock_gettime_nsec_np(int clk_id);")
    local probe_ok = pcall(function() return ffi.C.clock_gettime_nsec_np(8) end)
    if probe_ok then
      awake_clock = function() return ffi.C.clock_gettime_nsec_np(8) end
    end
  end
end
local started_awake = awake_clock and awake_clock() or nil
local started_wall_sec, started_wall_usec = uv.gettimeofday()

local function wall_elapsed_ms()
  if not started_wall_sec then
    return nil
  end
  local sec, usec = uv.gettimeofday()
  if not sec then
    return nil
  end
  return (sec - started_wall_sec) * 1000 + (usec - started_wall_usec) / 1000
end

local function awake_elapsed_ms()
  if not awake_clock then
    return nil
  end
  return tonumber(awake_clock() - started_awake) / 1e6
end

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

-- Report the argv the client was configured with and the executable Neovim
-- resolves it to, so the Go side fingerprints the binary that actually ran.
local function client_command(client)
  local cmd = client.config and client.config.cmd
  if type(cmd) ~= "table" then
    return nil, nil
  end
  local argv = {}
  for _, part in ipairs(cmd) do
    if type(part) == "string" then
      table.insert(argv, part)
    end
  end
  if #argv == 0 then
    return nil, nil
  end
  local path = vim.fn.exepath(argv[1])
  return argv, path ~= "" and path or nil
end

local function clients()
  local result = {}
  local opts = client_scope == "all" and {} or { bufnr = 0 }
  for _, client in ipairs(vim.lsp.get_clients(opts)) do
    local argv, path = client_command(client)
    table.insert(result, {
      name = client.name,
      initialized = client.initialized == true,
      cmd = argv,
      cmd_path = path,
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

  local finished_at = uv.hrtime()
  local payload = {
    schema_version = 3,
    probe = probe,
    expected_client = expected_client ~= "" and expected_client or nil,
    client_scope = probe == "lsp_ready" and (client_scope ~= "" and client_scope or "buffer") or nil,
    expected_namespace = expected_namespace ~= "" and expected_namespace or nil,
    status = status,
    elapsed_ms = (finished_at - started_at) / 1e6,
    wall_elapsed_ms = wall_elapsed_ms(),
    awake_elapsed_ms = awake_elapsed_ms(),
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
