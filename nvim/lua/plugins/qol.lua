return {
  {
    'MagicDuck/grug-far.nvim',
    cmd = { 'GrugFar' },
    opts = {},
    keys = {
      { '<leader>sR', '<cmd>GrugFar<CR>', desc = '[S]earch & [R]eplace (project)' },
    },
  },

  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = { 'markdown', 'codecompanion' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    opts = {
      file_types = { 'markdown', 'codecompanion' },
      heading = { sign = false },
      code = { sign = false, width = 'block', right_pad = 1 },
    },
  },

  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = function()
      local harpoon = require 'harpoon'
      return {
        {
          '<leader>ha',
          function()
            harpoon:list():add()
          end,
          desc = '[H]arpoon [A]dd file',
        },
        {
          '<leader>hl',
          function()
            harpoon.ui:toggle_quick_menu(harpoon:list())
          end,
          desc = '[H]arpoon [L]ist',
        },
        {
          '<C-1>',
          function()
            harpoon:list():select(1)
          end,
          desc = 'Harpoon slot 1',
        },
        {
          '<C-2>',
          function()
            harpoon:list():select(2)
          end,
          desc = 'Harpoon slot 2',
        },
        {
          '<C-3>',
          function()
            harpoon:list():select(3)
          end,
          desc = 'Harpoon slot 3',
        },
        {
          '<C-4>',
          function()
            harpoon:list():select(4)
          end,
          desc = 'Harpoon slot 4',
        },
      }
    end,
    config = function()
      require('harpoon'):setup()
    end,
  },
}
