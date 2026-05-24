return {
  {
    'tpope/vim-dadbod',
    cmd = { 'DB' },
  },
  {
    'kristijanhusak/vim-dadbod-ui',
    cmd = { 'DBUI', 'DBUIToggle', 'DBUIAddConnection', 'DBUIFindBuffer' },
    dependencies = { 'tpope/vim-dadbod' },
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
    end,
    keys = {
      { '<leader>du', '<cmd>DBUIToggle<CR>', desc = '[D]atabase [U]I toggle' },
      { '<leader>df', '<cmd>DBUIFindBuffer<CR>', desc = '[D]atabase [F]ind buffer' },
    },
  },
  {
    'kristijanhusak/vim-dadbod-completion',
    ft = { 'sql', 'mysql', 'plsql' },
    dependencies = { 'tpope/vim-dadbod' },
  },
}
