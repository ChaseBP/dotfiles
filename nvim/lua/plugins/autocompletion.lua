return {
  {
    'saghen/blink.cmp',
    event = { 'InsertEnter', 'CmdlineEnter' },
    version = '*',
    dependencies = {
      {
        'L3MON4D3/LuaSnip',
        version = 'v2.*',
        build = (function()
          if vim.fn.has 'win32' == 1 or vim.fn.executable 'make' == 0 then
            return
          end
          return 'make install_jsregexp'
        end)(),
        dependencies = {
          {
            'rafamadriz/friendly-snippets',
            config = function()
              require('luasnip.loaders.from_vscode').lazy_load()
            end,
          },
        },
      },
      {
        'folke/lazydev.nvim',
        ft = 'lua',
        opts = {
          library = {
            { path = '${3rd}/luv/library', words = { 'vim%.uv' } },
          },
        },
      },
      'saghen/blink.compat',
      'giuxtaposition/blink-cmp-copilot',
    },

    opts = {
      keymap = {
        preset = 'super-tab',
        ['<C-Space>'] = { 'show', 'show_documentation', 'hide_documentation' },
        ['<C-l>'] = { 'snippet_forward', 'fallback' },
        ['<C-h>'] = { 'snippet_backward', 'fallback' },
      },

      appearance = {
        nerd_font_variant = 'mono',
        kind_icons = {
          Copilot = '',
          Text = '󰉿',
          Method = '',
          Function = '󰊕',
          Constructor = '',
          Field = '',
          Variable = '󰆧',
          Class = '󰌗',
          Interface = '',
          Module = '',
          Property = '',
          Unit = '',
          Value = '󰎠',
          Enum = '',
          Keyword = '󰌋',
          Snippet = '',
          Color = '󰏘',
          File = '󰈙',
          Reference = '',
          Folder = '󰉋',
          EnumMember = '',
          Constant = '󰇽',
          Struct = '',
          Event = '',
          Operator = '󰆕',
          TypeParameter = '󰊄',
        },
      },

      completion = {
        accept = { auto_brackets = { enabled = true } },
        list = { selection = { preselect = false, auto_insert = true } },
        menu = {
          border = 'rounded',
          draw = {
            columns = { { 'kind_icon' }, { 'label', 'label_description', gap = 1 }, { 'source_name' } },
          },
        },
        documentation = {
          auto_show = true,
          auto_show_delay_ms = 200,
          window = { border = 'rounded' },
        },
        ghost_text = { enabled = true },
      },

      signature = {
        enabled = true,
        window = { border = 'rounded' },
      },

      sources = {
        default = { 'lazydev', 'lsp', 'snippets', 'path', 'buffer', 'copilot' },
        per_filetype = {
          sql = { 'dadbod', 'snippets', 'buffer' },
          mysql = { 'dadbod', 'snippets', 'buffer' },
          plsql = { 'dadbod', 'snippets', 'buffer' },
        },
        providers = {
          lazydev = {
            name = 'LazyDev',
            module = 'lazydev.integrations.blink',
            score_offset = 100,
          },
          copilot = {
            name = 'copilot',
            module = 'blink-cmp-copilot',
            score_offset = 100,
            async = true,
            transform_items = function(_, items)
              local CompletionItemKind = require('blink.cmp.types').CompletionItemKind
              local kind_idx = #CompletionItemKind + 1
              CompletionItemKind[kind_idx] = 'Copilot'
              for _, item in ipairs(items) do
                item.kind = kind_idx
              end
              return items
            end,
          },
          dadbod = {
            name = 'vim-dadbod-completion',
            module = 'blink.compat.source',
            score_offset = 90,
          },
        },
      },

      snippets = { preset = 'luasnip' },

      cmdline = {
        keymap = { preset = 'cmdline' },
        completion = { menu = { auto_show = true } },
      },

      fuzzy = { implementation = 'prefer_rust_with_warning' },
    },

    opts_extend = { 'sources.default' },
  },
}
