local opt = vim.opt

opt.number = true
opt.relativenumber = true
opt.clipboard = 'unnamedplus'
opt.wrap = false
opt.linebreak = true
opt.mouse = 'a'
opt.autoindent = true
opt.ignorecase = true
opt.smartcase = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.softtabstop = 2
opt.expandtab = true
opt.scrolloff = 4
opt.sidescrolloff = 8
opt.cursorline = false
opt.cursorcolumn = false
opt.splitbelow = true
opt.splitright = true
opt.hlsearch = false
opt.showmode = false
opt.termguicolors = true
opt.whichwrap = 'bs<>[]hl'
opt.numberwidth = 4
opt.swapfile = false
opt.smartindent = true
opt.showtabline = 2
opt.backspace = 'indent,eol,start'
opt.pumheight = 10
opt.conceallevel = 0
opt.signcolumn = 'yes'
opt.fileencoding = 'utf-8'
opt.cmdheight = 1
opt.breakindent = true
opt.updatetime = 250
opt.timeoutlen = 300
opt.backup = false
opt.writebackup = false
opt.undofile = true
opt.completeopt = 'menuone,noselect'
opt.confirm = true
opt.inccommand = 'split'
opt.splitkeep = 'screen'
opt.virtualedit = 'block'
opt.smoothscroll = true
opt.winborder = 'rounded'
opt.jumpoptions = 'view'
opt.list = true
opt.listchars = {
  tab = '» ',
  trail = '·',
  nbsp = '␣',
  extends = '›',
  precedes = '‹',
}
opt.fillchars = {
  eob = ' ',
  fold = ' ',
  foldopen = '',
  foldsep = ' ',
  foldclose = '',
}
opt.foldlevel = 99
opt.foldlevelstart = 99
opt.foldenable = true
opt.foldmethod = 'expr'
opt.foldexpr = 'v:lua.vim.treesitter.foldexpr()'

opt.shortmess:append 'c'
opt.iskeyword:append '-'
opt.formatoptions:remove { 'c', 'r', 'o' }
opt.diffopt:append 'linematch:60'
opt.runtimepath:remove '/usr/share/vim/vimfiles'

vim.g.have_nerd_font = true

if vim.fn.executable 'rg' == 1 then
  opt.grepprg = 'rg --vimgrep --smart-case --hidden'
  opt.grepformat = '%f:%l:%c:%m'
end
