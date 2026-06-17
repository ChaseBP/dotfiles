-- Java LSP via nvim-jdtls.
--
-- Driven from ftplugin so it runs per Java buffer (jdtls needs one server per
-- project workspace, unlike the servers in lua/plugins/lsp.lua). jdtls is NOT in
-- that file's `servers` table and mason-lspconfig has automatic_enable = false, so
-- there is no double-start. Keymaps come from the global LspAttach autocmd in
-- lua/plugins/lsp.lua, which fires for this client too -- nothing to redefine here.

local ok, jdtls = pcall(require, 'jdtls')
if not ok then
  return
end

local mason_jdtls = vim.fn.stdpath 'data' .. '/mason/packages/jdtls'

local launcher = vim.fn.glob(mason_jdtls .. '/plugins/org.eclipse.equinox.launcher_*.jar')
if launcher == '' then
  vim.notify('[jdtls] launcher jar not found under ' .. mason_jdtls .. ' -- install jdtls via :Mason', vim.log.levels.WARN)
  return
end

-- jdtls ships a per-OS/arch launch configuration; pick the right one so this
-- works unchanged on Linux/macOS/Windows and x86_64/arm.
local function config_subdir()
  local uname = (vim.uv or vim.loop).os_uname()
  local is_arm = uname.machine == 'aarch64' or uname.machine == 'arm64'
  if uname.sysname == 'Darwin' then
    return is_arm and 'config_mac_arm' or 'config_mac'
  elseif uname.sysname:find 'Windows' then
    return 'config_win'
  else
    return is_arm and 'config_linux_arm' or 'config_linux'
  end
end

local config_dir = mason_jdtls .. '/' .. config_subdir()
local lombok = mason_jdtls .. '/lombok.jar'

-- jdtls is a Java program: prefer an explicit JDK (JDTLS_JAVA_HOME/JAVA_HOME),
-- else fall back to `java` on PATH. Bail with a clear message if none is runnable.
local java_home = vim.env.JDTLS_JAVA_HOME or vim.env.JAVA_HOME
local java_bin = (java_home and java_home ~= '') and (java_home .. '/bin/java') or 'java'
if vim.fn.executable(java_bin) == 0 then
  vim.notify('[jdtls] no runnable `java` found (needs JDK 21+); set JAVA_HOME or add java to PATH', vim.log.levels.WARN)
  return
end

-- Resolve the workspace root.
--
-- eclipse.jdt.ls only grants *full* features (semantic diagnostics, type errors)
-- when it can build an "invisible project", and it only does that when the inferred
-- source root is a SUBDIRECTORY of the workspace root -- conventionally a `src/`
-- folder. A .java file sitting directly in the workspace root falls back to
-- standalone mode ("non-project file, only syntax errors are reported").
--
-- So: 1) honour real build-tool / git projects; 2) for a file under a `src/` folder,
-- use src's parent as root so `src/` becomes the source root -> full diagnostics;
-- 3) otherwise fall back to the file's own dir (syntax-only -- the jdtls limitation).
local function resolve_root()
  local found = require('jdtls.setup').find_root {
    '.git',
    'mvnw',
    'gradlew',
    'pom.xml',
    'build.gradle',
    'build.gradle.kts',
    'settings.gradle',
  }
  if found then
    return found
  end

  local file = vim.fn.expand '%:p'
  local src = vim.fs.find('src', { path = vim.fs.dirname(file), upward = true, type = 'directory' })[1]
  if src then
    return vim.fs.dirname(src)
  end

  return vim.fs.dirname(file)
end

local root_dir = resolve_root()

-- One data dir per root so projects and standalone dirs never share a workspace.
local workspace = vim.fn.stdpath 'data' .. '/jdtls-workspace/' .. vim.fn.fnamemodify(root_dir, ':p:h:t')

-- Self-contained capabilities (mirrors lua/plugins/lsp.lua, which builds these locally).
local capabilities = vim.tbl_deep_extend(
  'force',
  vim.lsp.protocol.make_client_capabilities(),
  require('blink.cmp').get_lsp_capabilities()
)

local config = {
  cmd = {
    java_bin,
    '-Declipse.application=org.eclipse.jdt.ls.core.id1',
    '-Dosgi.bundles.defaultStartLevel=4',
    '-Declipse.product=org.eclipse.jdt.ls.core.product',
    '-Dlog.protocol=true',
    '-Dlog.level=ALL',
    '-Xmx1g',
    '--add-modules=ALL-SYSTEM',
    '--add-opens',
    'java.base/java.util=ALL-UNNAMED',
    '--add-opens',
    'java.base/java.lang=ALL-UNNAMED',
    '-javaagent:' .. lombok,
    '-jar',
    launcher,
    '-configuration',
    config_dir,
    '-data',
    workspace,
  },
  root_dir = root_dir,
  capabilities = capabilities,
  settings = {
    java = {},
  },
  init_options = {
    bundles = {},
  },
}

jdtls.start_or_attach(config)
