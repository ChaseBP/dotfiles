local augroup = function(name)
  return vim.api.nvim_create_augroup('user-' .. name, { clear = true })
end

vim.diagnostic.config {
  severity_sort = true,
  update_in_insert = false,
  virtual_text = {
    spacing = 4,
    source = 'if_many',
    prefix = '●',
  },
  float = {
    source = true,
    border = 'rounded',
  },
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = '',
      [vim.diagnostic.severity.WARN] = '',
      [vim.diagnostic.severity.INFO] = '',
      [vim.diagnostic.severity.HINT] = '󰌵',
    },
  },
}

vim.api.nvim_create_autocmd('TextYankPost', {
  group = augroup 'highlight-yank',
  callback = function()
    (vim.hl or vim.highlight).on_yank { higroup = 'IncSearch', timeout = 180 }
  end,
})

vim.api.nvim_create_autocmd('BufReadPost', {
  group = augroup 'restore-cursor',
  callback = function(event)
    local mark = vim.api.nvim_buf_get_mark(event.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(event.buf)
    if mark[1] > 0 and mark[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

vim.api.nvim_create_autocmd('VimResized', {
  group = augroup 'resize-splits',
  command = 'tabdo wincmd =',
})

vim.api.nvim_create_autocmd('FileType', {
  group = augroup 'close-with-q',
  pattern = {
    'checkhealth',
    'help',
    'lspinfo',
    'man',
    'notify',
    'qf',
    'query',
    'startuptime',
    'tsplayground',
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = event.buf, silent = true, desc = 'Close window' })
  end,
})

vim.api.nvim_create_autocmd('BufWritePre', {
  group = augroup 'create-parent-dirs',
  callback = function(event)
    if event.match:match '^%w%w+:[\\/][\\/]' then
      return
    end

    local file = vim.uv.fs_realpath(event.match) or event.match
    local dir = vim.fn.fnamemodify(file, ':p:h')
    if vim.fn.isdirectory(dir) == 0 then
      vim.fn.mkdir(dir, 'p')
    end
  end,
})
