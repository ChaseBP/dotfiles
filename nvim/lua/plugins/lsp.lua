return {
  'neovim/nvim-lspconfig',
  event = { 'BufReadPre', 'BufNewFile' },
  dependencies = {
    { 'williamboman/mason.nvim', config = true },
    'williamboman/mason-lspconfig.nvim',
    'WhoIsSethDaniel/mason-tool-installer.nvim',
    { 'j-hui/fidget.nvim', opts = {} },
    'b0o/schemastore.nvim',
    'saghen/blink.cmp',
  },
  config = function()
    local capabilities = vim.tbl_deep_extend(
      'force',
      vim.lsp.protocol.make_client_capabilities(),
      require('blink.cmp').get_lsp_capabilities()
    )

    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('user-lsp-attach', { clear = true }),
      callback = function(event)
        local map = function(keys, func, desc, mode)
          vim.keymap.set(mode or 'n', keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
        end

        local telescope = require 'telescope.builtin'
        local client = vim.lsp.get_client_by_id(event.data.client_id)

        map('gd', telescope.lsp_definitions, '[G]oto [D]efinition')
        map('gr', telescope.lsp_references, '[G]oto [R]eferences')
        map('gI', telescope.lsp_implementations, '[G]oto [I]mplementation')
        map('gD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')
        map('<leader>D', telescope.lsp_type_definitions, 'Type [D]efinition')
        map('<leader>ds', telescope.lsp_document_symbols, '[D]ocument [S]ymbols')
        map('<leader>ws', telescope.lsp_dynamic_workspace_symbols, '[W]orkspace [S]ymbols')
        map('<leader>rn', vim.lsp.buf.rename, '[R]e[n]ame')
        map('<leader>ca', vim.lsp.buf.code_action, '[C]ode [A]ction', { 'n', 'x' })
        map('K', vim.lsp.buf.hover, 'Hover Documentation')
        map('<leader>k', vim.lsp.buf.signature_help, 'Signature Help')

        if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_documentHighlight) then
          local highlight_group = vim.api.nvim_create_augroup('user-lsp-highlight', { clear = false })
          vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
            buffer = event.buf,
            group = highlight_group,
            callback = vim.lsp.buf.document_highlight,
          })
          vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
            buffer = event.buf,
            group = highlight_group,
            callback = vim.lsp.buf.clear_references,
          })
          vim.api.nvim_create_autocmd('LspDetach', {
            buffer = event.buf,
            group = vim.api.nvim_create_augroup('user-lsp-detach', { clear = true }),
            callback = function(detach_event)
              vim.lsp.buf.clear_references()
              vim.api.nvim_clear_autocmds { group = 'user-lsp-highlight', buffer = detach_event.buf }
            end,
          })
        end

        if client and client:supports_method(vim.lsp.protocol.Methods.textDocument_inlayHint) then
          map('<leader>th', function()
            vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf }, { bufnr = event.buf })
          end, '[T]oggle Inlay [H]ints')
        end
      end,
    })

    local servers = {
      bashls = {},
      cssls = {},
      docker_compose_language_service = {},
      dockerls = {},
      gopls = {},
      html = { filetypes = { 'html', 'twig', 'hbs' } },
      jsonls = {
        settings = {
          json = {
            schemas = require('schemastore').json.schemas(),
            validate = { enable = true },
          },
        },
      },
      marksman = {},
      pyright = {
        settings = {
          pyright = { disableOrganizeImports = true },
          python = { analysis = { typeCheckingMode = 'basic', diagnosticMode = 'openFilesOnly' } },
        },
      },
      ruff = {},
      sqlls = {},
      taplo = {},
      tailwindcss = {},
      terraformls = {},
      ts_ls = {},
      yamlls = {
        settings = {
          yaml = {
            keyOrdering = false,
            format = { enable = false },
            validate = true,
            schemaStore = { enable = false, url = '' },
            schemas = require('schemastore').yaml.schemas(),
          },
        },
      },
      lua_ls = {
        settings = {
          Lua = {
            completion = { callSnippet = 'Replace' },
            runtime = { version = 'LuaJIT' },
            workspace = {
              checkThirdParty = false,
              library = vim.api.nvim_get_runtime_file('', true),
            },
            diagnostics = { disable = { 'missing-fields' } },
            format = { enable = false },
          },
        },
      },
    }

    local ahk_server = {
      cmd = {
        'node',
        vim.fn.expand '/home/raven/vscode-autohotkey2-lsp/server/dist/server.js',
        '--stdio',
      },
      filetypes = { 'ahk', 'autohotkey', 'ah2' },
      init_options = {
        locale = 'en-us',
        InterpreterPath = '/mnt/c/Program Files/AutoHotkey/v2/AutoHotkey.exe',
      },
      single_file_support = true,
      flags = { debounce_text_changes = 500 },
    }

    require('mason').setup()

    local ensure_installed = vim.tbl_keys(servers)
    vim.list_extend(ensure_installed, {
      'checkmake',
      'jdtls',
      'eslint_d',
      'prettier',
      'ruff',
      'shellcheck',
      'shfmt',
      'stylua',
    })
    require('mason-tool-installer').setup { ensure_installed = ensure_installed }

    require('mason-lspconfig').setup {
      ensure_installed = vim.tbl_keys(servers),
      automatic_enable = false,
    }

    for server_name, server in pairs(servers) do
      server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, server.capabilities or {})
      vim.lsp.config(server_name, server)
    end

    ahk_server.capabilities = vim.tbl_deep_extend('force', {}, capabilities, ahk_server.capabilities or {})
    vim.lsp.config('ahk2', ahk_server)

    local enable_list = vim.tbl_keys(servers)
    table.insert(enable_list, 'ahk2')
    vim.lsp.enable(enable_list)
  end,
}
