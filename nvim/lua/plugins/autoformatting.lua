return {
  {
    'stevearc/conform.nvim',
    event = { 'BufWritePre' },
    cmd = { 'ConformInfo' },
    keys = {
      {
        '<leader>cf',
        function()
          require('conform').format { async = true, lsp_format = 'fallback' }
        end,
        mode = { 'n', 'v' },
        desc = '[C]ode [F]ormat',
      },
    },
    opts = {
      formatters_by_ft = {
        lua = { 'stylua' },
        python = { 'ruff_organize_imports', 'ruff_format' },
        javascript = { 'prettier' },
        javascriptreact = { 'prettier' },
        typescript = { 'prettier' },
        typescriptreact = { 'prettier' },
        html = { 'prettier' },
        css = { 'prettier' },
        scss = { 'prettier' },
        json = { 'prettier' },
        jsonc = { 'prettier' },
        yaml = { 'prettier' },
        markdown = { 'prettier' },
        ['markdown.mdx'] = { 'prettier' },
        sh = { 'shfmt' },
        bash = { 'shfmt' },
        zsh = { 'shfmt' },
        terraform = { 'terraform_fmt' },
        terraform_vars = { 'terraform_fmt' },
        tf = { 'terraform_fmt' },
        toml = { 'taplo' },
      },
      format_on_save = function(bufnr)
        if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
          return
        end

        return { timeout_ms = 1000, lsp_format = 'fallback' }
      end,
    },
    config = function(_, opts)
      require('conform').setup(opts)

      vim.api.nvim_create_user_command('FormatDisable', function(args)
        if args.bang then
          vim.b.disable_autoformat = true
        else
          vim.g.disable_autoformat = true
        end
      end, { bang = true, desc = 'Disable autoformat-on-save' })

      vim.api.nvim_create_user_command('FormatEnable', function()
        vim.b.disable_autoformat = false
        vim.g.disable_autoformat = false
      end, { desc = 'Enable autoformat-on-save' })
    end,
  },
  {
    'mfussenegger/nvim-lint',
    event = { 'BufReadPost', 'BufWritePost', 'InsertLeave' },
    config = function()
      local lint = require 'lint'

      lint.linters_by_ft = {
        python = { 'ruff' },
        javascript = { 'eslint_d' },
        javascriptreact = { 'eslint_d' },
        typescript = { 'eslint_d' },
        typescriptreact = { 'eslint_d' },
        make = { 'checkmake' },
        sh = { 'shellcheck' },
        bash = { 'shellcheck' },
        zsh = { 'shellcheck' },
      }

      local lint_augroup = vim.api.nvim_create_augroup('nvim-lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          lint.try_lint()
        end,
      })

      vim.keymap.set('n', '<leader>cl', function()
        lint.try_lint()
      end, { desc = '[C]ode [L]int' })

      vim.api.nvim_create_user_command('LintInfo', function()
        local ft = vim.bo.filetype
        local linters = lint.linters_by_ft[ft] or {}
        vim.notify(('Linters for %s: %s'):format(ft ~= '' and ft or 'current buffer', table.concat(linters, ', ')), vim.log.levels.INFO)
      end, { desc = 'Show configured linters for the current filetype' })
    end,
  },
}
