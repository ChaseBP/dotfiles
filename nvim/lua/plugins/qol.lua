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
    ft = { 'markdown' },
    dependencies = { 'nvim-treesitter/nvim-treesitter', 'nvim-tree/nvim-web-devicons' },
    opts = {
      file_types = { 'markdown' },
      heading = { sign = false },
      code = { sign = false, width = 'block', right_pad = 1 },
      pipe_table = { cell = 'padded', wrap = true },
      -- Keep ordinary formatting visible under the cursor in Normal mode.
      anti_conceal = { disabled_modes = { 'n' } },
      win_options = {
        wrap = { default = vim.o.wrap, rendered = true },
        concealcursor = { default = vim.o.concealcursor, rendered = 'nc' },
      },
      -- Give :RenderMarkdown preview a clean reading layout.
      overrides = {
        preview = {
          anti_conceal = { enabled = false },
          win_options = {
            number = { default = vim.o.number, rendered = false },
            relativenumber = { default = vim.o.relativenumber, rendered = false },
            signcolumn = { default = vim.o.signcolumn, rendered = 'no' },
            list = { default = vim.o.list, rendered = false },
          },
        },
      },
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
