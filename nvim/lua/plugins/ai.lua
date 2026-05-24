return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
      filetypes = {
        yaml = true,
        markdown = true,
        gitcommit = false,
        gitrebase = false,
        help = false,
        ['.'] = false,
        ['*'] = true,
      },
    },
  },

  {
    'olimorris/codecompanion.nvim',
    cmd = {
      'CodeCompanion',
      'CodeCompanionChat',
      'CodeCompanionActions',
      'CodeCompanionCmd',
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    opts = {
      strategies = {
        chat = { adapter = 'copilot' },
        inline = { adapter = 'copilot' },
        cmd = { adapter = 'copilot' },
      },
      display = {
        chat = {
          window = { width = 0.35 },
          show_settings = false,
        },
        diff = { provider = 'default' },
      },
    },
    keys = {
      { '<leader>aa', '<cmd>CodeCompanionActions<CR>', mode = { 'n', 'v' }, desc = '[A]I [A]ctions' },
      { '<leader>ac', '<cmd>CodeCompanionChat Toggle<CR>', mode = { 'n', 'v' }, desc = '[A]I [C]hat toggle' },
      { '<leader>ai', ':CodeCompanion ', mode = { 'n', 'v' }, desc = '[A]I [I]nline prompt' },
      { '<leader>ap', '<cmd>CodeCompanionChat Add<CR>', mode = 'v', desc = '[A]I [P]aste selection to chat' },
    },
    init = function()
      vim.cmd [[cab cc CodeCompanion]]
    end,
  },
}
