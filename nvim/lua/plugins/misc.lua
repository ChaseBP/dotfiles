return {
  {
    'christoomey/vim-tmux-navigator',
    keys = {
      { '<C-h>', '<cmd>TmuxNavigateLeft<CR>', desc = 'Navigate left' },
      { '<C-j>', '<cmd>TmuxNavigateDown<CR>', desc = 'Navigate down' },
      { '<C-k>', '<cmd>TmuxNavigateUp<CR>', desc = 'Navigate up' },
      { '<C-l>', '<cmd>TmuxNavigateRight<CR>', desc = 'Navigate right' },
    },
  },
  {
    'tpope/vim-sleuth',
    event = { 'BufReadPost', 'BufNewFile' },
  },
  {
    'tpope/vim-fugitive',
    cmd = { 'G', 'Git', 'Gdiffsplit', 'Gread', 'Gwrite', 'Ggrep', 'GMove', 'GDelete', 'GBrowse' },
    keys = {
      { '<leader>gs', '<cmd>Git<CR>', desc = '[G]it [S]tatus' },
      { '<leader>gc', '<cmd>Git commit<CR>', desc = '[G]it [C]ommit' },
      { '<leader>gp', '<cmd>Git push<CR>', desc = '[G]it [P]ush' },
      { '<leader>gl', '<cmd>Git log --oneline<CR>', desc = '[G]it [L]og' },
    },
  },
  {
    'tpope/vim-rhubarb',
    cmd = { 'GBrowse' },
    dependencies = { 'tpope/vim-fugitive' },
  },
  {
    'folke/which-key.nvim',
    event = 'VeryLazy',
    opts = {
      spec = {
        { '<leader>a', group = 'ai' },
        { '<leader>b', group = 'buffer' },
        { '<leader>c', group = 'code' },
        { '<leader>d', group = 'diagnostics/database' },
        { '<leader>g', group = 'git' },
        { '<leader>h', group = 'hunks/harpoon' },
        { '<leader>l', group = 'line' },
        { '<leader>n', group = 'neo-tree' },
        { '<leader>s', group = 'search/save' },
        { '<leader>t', group = 'tabs/toggles' },
        { '<leader>w', group = 'windows/workspace' },
        { '<leader>x', group = 'trouble' },
      },
    },
  },
  {
    'windwp/nvim-autopairs',
    event = 'InsertEnter',
    opts = {},
  },
  {
    'folke/todo-comments.nvim',
    event = { 'BufReadPost', 'BufNewFile' },
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = { signs = false },
    keys = {
      {
        ']t',
        function()
          require('todo-comments').jump_next()
        end,
        desc = 'Next todo comment',
      },
      {
        '[t',
        function()
          require('todo-comments').jump_prev()
        end,
        desc = 'Previous todo comment',
      },
      { '<leader>st', '<cmd>TodoTelescope<CR>', desc = '[S]earch [T]odos' },
    },
  },
  {
    'norcalli/nvim-colorizer.lua',
    event = { 'BufReadPost', 'BufNewFile' },
    config = function()
      require('colorizer').setup()
    end,
  },
  {
    'folke/trouble.nvim',
    cmd = 'Trouble',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {},
    keys = {
      { '<leader>xx', '<cmd>Trouble diagnostics toggle<CR>', desc = 'Diagnostics' },
      { '<leader>xX', '<cmd>Trouble diagnostics toggle filter.buf=0<CR>', desc = 'Buffer diagnostics' },
      { '<leader>cS', '<cmd>Trouble symbols toggle focus=false<CR>', desc = '[C]ode [S]ymbols' },
      { '<leader>cL', '<cmd>Trouble lsp toggle focus=false win.position=right<CR>', desc = '[C]ode [L]SP refs/defs' },
      { '<leader>xL', '<cmd>Trouble loclist toggle<CR>', desc = 'Location list' },
      { '<leader>xQ', '<cmd>Trouble qflist toggle<CR>', desc = 'Quickfix list' },
    },
  },
  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    opts = {
      modes = {
        char = { enabled = false },
      },
    },
    keys = {
      {
        's',
        mode = { 'n', 'x', 'o' },
        function()
          require('flash').jump()
        end,
        desc = 'Flash jump',
      },
      {
        'S',
        mode = { 'n', 'x', 'o' },
        function()
          require('flash').treesitter()
        end,
        desc = 'Flash treesitter',
      },
      {
        'r',
        mode = 'o',
        function()
          require('flash').remote()
        end,
        desc = 'Remote flash',
      },
      {
        '<c-s>',
        mode = { 'c' },
        function()
          require('flash').toggle()
        end,
        desc = 'Toggle flash search',
      },
    },
  },
  {
    'echasnovski/mini.nvim',
    version = false,
    event = 'VeryLazy',
    config = function()
      require('mini.ai').setup { n_lines = 500 }
      require('mini.bufremove').setup()
      require('mini.move').setup()
      require('mini.splitjoin').setup()
      require('mini.surround').setup {
        mappings = {
          add = 'gsa',
          delete = 'gsd',
          find = 'gsf',
          find_left = 'gsF',
          highlight = 'gsh',
          replace = 'gsr',
          update_n_lines = 'gsn',
        },
      }
    end,
  },
}
