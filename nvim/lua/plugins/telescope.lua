local telescope_key = function(lhs, picker, desc)
  return {
    lhs,
    function()
      require('telescope.builtin')[picker]()
    end,
    desc = desc,
  }
end

return {
  'nvim-telescope/telescope.nvim',
  cmd = 'Telescope',
  branch = '0.1.x',
  keys = {
    telescope_key('<leader>sh', 'help_tags', '[S]earch [H]elp'),
    telescope_key('<leader>sk', 'keymaps', '[S]earch [K]eymaps'),
    telescope_key('<leader>sf', 'find_files', '[S]earch [F]iles'),
    telescope_key('<leader>ss', 'builtin', '[S]earch [S]elect Telescope'),
    telescope_key('<leader>sw', 'grep_string', '[S]earch current [W]ord'),
    telescope_key('<leader>sg', 'live_grep', '[S]earch by [G]rep'),
    telescope_key('<leader>sd', 'diagnostics', '[S]earch [D]iagnostics'),
    telescope_key('<leader>sr', 'resume', '[S]earch [R]esume'),
    telescope_key('<leader>s.', 'oldfiles', '[S]earch Recent Files'),
    telescope_key('<leader><leader>', 'buffers', 'Find existing buffers'),
    {
      '<leader>/',
      function()
        require('telescope.builtin').current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
          winblend = 10,
          previewer = false,
        })
      end,
      desc = 'Fuzzily search in current buffer',
    },
    {
      '<leader>s/',
      function()
        require('telescope.builtin').live_grep {
          grep_open_files = true,
          prompt_title = 'Live Grep in Open Files',
        }
      end,
      desc = '[S]earch in open files',
    },
  },
  dependencies = {
    'nvim-lua/plenary.nvim',
    {
      'nvim-telescope/telescope-fzf-native.nvim',
      build = 'make',
      cond = function()
        return vim.fn.executable 'make' == 1
      end,
    },
    { 'nvim-telescope/telescope-ui-select.nvim' },
    { 'nvim-tree/nvim-web-devicons', enabled = vim.g.have_nerd_font },
  },
  config = function()
    local telescope = require 'telescope'
    local actions = require 'telescope.actions'

    telescope.setup {
      defaults = {
        file_ignore_patterns = { 'node_modules', '.git/', '.venv/', 'dist/', 'build/', 'target/' },
        mappings = {
          i = {
            ['<C-k>'] = actions.move_selection_previous,
            ['<C-j>'] = actions.move_selection_next,
            ['<C-l>'] = actions.select_default,
          },
        },
      },
      pickers = {
        find_files = {
          hidden = true,
        },
        live_grep = {
          additional_args = function()
            return { '--hidden' }
          end,
        },
      },
      extensions = {
        ['ui-select'] = {
          require('telescope.themes').get_dropdown(),
        },
      },
    }

    pcall(telescope.load_extension, 'fzf')
    pcall(telescope.load_extension, 'ui-select')
  end,
}
