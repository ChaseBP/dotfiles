vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

local map = vim.keymap.set
local opts = { noremap = true, silent = true }

map({ 'n', 'v' }, '<Space>', '<Nop>', { silent = true, desc = 'Disable space default' })

map('n', '<C-s>', '<cmd>w<CR>', vim.tbl_extend('force', opts, { desc = 'Save file' }))
map('n', '<leader>sn', '<cmd>noautocmd w<CR>', vim.tbl_extend('force', opts, { desc = 'Save without formatting' }))
map('n', '<C-q>', '<cmd>q<CR>', vim.tbl_extend('force', opts, { desc = 'Quit window' }))

map('n', 'x', '"_x', vim.tbl_extend('force', opts, { desc = 'Delete char without yanking' }))
map({ 'n', 'x' }, '<leader>v', '<C-v>', vim.tbl_extend('force', opts, { desc = 'Visual block mode' }))
map('n', '<C-d>', '<C-d>zz', vim.tbl_extend('force', opts, { desc = 'Scroll down and center' }))
map('n', '<C-u>', '<C-u>zz', vim.tbl_extend('force', opts, { desc = 'Scroll up and center' }))
map('n', 'n', 'nzzzv', vim.tbl_extend('force', opts, { desc = 'Next search result centered' }))
map('n', 'N', 'Nzzzv', vim.tbl_extend('force', opts, { desc = 'Previous search result centered' }))

map('n', '<Up>', '<cmd>resize -2<CR>', vim.tbl_extend('force', opts, { desc = 'Decrease window height' }))
map('n', '<Down>', '<cmd>resize +2<CR>', vim.tbl_extend('force', opts, { desc = 'Increase window height' }))
map('n', '<Right>', '<cmd>vertical resize -2<CR>', vim.tbl_extend('force', opts, { desc = 'Decrease window width' }))
map('n', '<Left>', '<cmd>vertical resize +2<CR>', vim.tbl_extend('force', opts, { desc = 'Increase window width' }))

map('n', '<Tab>', '<cmd>bnext<CR>', vim.tbl_extend('force', opts, { desc = 'Next buffer' }))
map('n', '<S-Tab>', '<cmd>bprevious<CR>', vim.tbl_extend('force', opts, { desc = 'Previous buffer' }))
map('n', '<leader>bd', function()
  require('mini.bufremove').delete(0, false)
end, { desc = '[B]uffer [D]elete' })
map('n', '<leader>bn', '<cmd>enew<CR>', vim.tbl_extend('force', opts, { desc = '[B]uffer [N]ew' }))

map('n', '<leader>wv', '<C-w>v', vim.tbl_extend('force', opts, { desc = '[W]indow split [V]ertical' }))
map('n', '<leader>ws', '<C-w>s', vim.tbl_extend('force', opts, { desc = '[W]indow split horizontal' }))
map('n', '<leader>we', '<C-w>=', vim.tbl_extend('force', opts, { desc = '[W]indow equalize' }))
map('n', '<leader>wq', '<cmd>close<CR>', vim.tbl_extend('force', opts, { desc = '[W]indow [Q]uit' }))

map('n', '<leader>to', '<cmd>tabnew<CR>', vim.tbl_extend('force', opts, { desc = '[T]ab [O]pen' }))
map('n', '<leader>tx', '<cmd>tabclose<CR>', vim.tbl_extend('force', opts, { desc = '[T]ab close' }))
map('n', '<leader>tn', '<cmd>tabn<CR>', vim.tbl_extend('force', opts, { desc = '[T]ab [N]ext' }))
map('n', '<leader>tp', '<cmd>tabp<CR>', vim.tbl_extend('force', opts, { desc = '[T]ab [P]revious' }))

map('n', '<leader>lw', '<cmd>set wrap!<CR>', vim.tbl_extend('force', opts, { desc = '[L]ine [W]rap toggle' }))
map('v', '<', '<gv', vim.tbl_extend('force', opts, { desc = 'Indent left and reselect' }))
map('v', '>', '>gv', vim.tbl_extend('force', opts, { desc = 'Indent right and reselect' }))
map('v', 'p', '"_dP', vim.tbl_extend('force', opts, { desc = 'Paste without replacing yank' }))

map('n', '[d', function()
  vim.diagnostic.jump { count = -1, float = true }
end, { desc = 'Previous diagnostic' })
map('n', ']d', function()
  vim.diagnostic.jump { count = 1, float = true }
end, { desc = 'Next diagnostic' })
map('n', '<leader>d', vim.diagnostic.open_float, { desc = 'Open diagnostic float' })
map('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic location list' })
map('n', '[q', '<cmd>cprevious<CR>', vim.tbl_extend('force', opts, { desc = 'Previous quickfix item' }))
map('n', ']q', '<cmd>cnext<CR>', vim.tbl_extend('force', opts, { desc = 'Next quickfix item' }))
