-- nvim 0.12-dev compat: vim.fs.find doesn't handle nested table markers used
-- by nvim-lspconfig on 0.11.3+ (root_markers = { {group1}, {group2} }).
-- Flatten nested tables so joinpath never receives a table argument.
local _fs_find = vim.fs.find
vim.fs.find = function(names, opts)
  if type(names) == 'table' then
    local flat = {}
    for _, v in ipairs(names) do
      if type(v) == 'table' then
        vim.list_extend(flat, v)
      else
        flat[#flat + 1] = v
      end
    end
    names = flat
  end
  return _fs_find(names, opts)
end

-- Suppress vim.tbl_flatten deprecation warning emitted by older plugins (e.g. neo-tree).
vim.tbl_flatten = function(t)
  return vim.iter(t):flatten(math.huge):totable()
end

require 'core.options'
require 'core.keymaps'
require 'core.autocmds'

local lazypath = vim.fn.stdpath 'data' .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system { 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath }
  if vim.v.shell_error ~= 0 then
    error('Error cloning lazy.nvim:\n' .. out)
  end
end
vim.opt.rtp:prepend(lazypath)

require('lazy').setup({
  require 'plugins.neotree',
  require 'plugins.bufferline',
  require 'plugins.colortheme',
  require 'plugins.lualine',
  require 'plugins.treesitter',
  require 'plugins.telescope',
  require 'plugins.lsp',
  require 'plugins.jdtls',
  require 'plugins.autocompletion',
  require 'plugins.autoformatting',
  require 'plugins.gitsigns',
  require 'plugins.alpha',
  require 'plugins.indent-blankline',
  require 'plugins.misc',
  require 'plugins.sql-plugins',
  require 'plugins.ai',
  require 'plugins.qol',
}, {
  rocks = { enabled = false },
})
