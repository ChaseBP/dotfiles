return {
  'lewis6991/gitsigns.nvim',
  event = { 'BufReadPre', 'BufNewFile' },
  opts = {
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    signs_staged = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
    on_attach = function(bufnr)
      local gitsigns = require 'gitsigns'
      local map = function(mode, lhs, rhs, desc)
        vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
      end

      map('n', ']c', function()
        if vim.wo.diff then
          vim.cmd.normal { ']c', bang = true }
          return
        end
        gitsigns.next_hunk()
      end, 'Next git hunk')

      map('n', '[c', function()
        if vim.wo.diff then
          vim.cmd.normal { '[c', bang = true }
          return
        end
        gitsigns.prev_hunk()
      end, 'Previous git hunk')

      map('n', '<leader>hs', gitsigns.stage_hunk, '[H]unk [S]tage')
      map('n', '<leader>hr', gitsigns.reset_hunk, '[H]unk [R]eset')
      map('v', '<leader>hs', function()
        gitsigns.stage_hunk { vim.fn.line '.', vim.fn.line 'v' }
      end, '[H]unk [S]tage')
      map('v', '<leader>hr', function()
        gitsigns.reset_hunk { vim.fn.line '.', vim.fn.line 'v' }
      end, '[H]unk [R]eset')
      map('n', '<leader>hS', gitsigns.stage_buffer, '[H]unk [S]tage buffer')
      map('n', '<leader>hu', gitsigns.undo_stage_hunk, '[H]unk [U]ndo stage')
      map('n', '<leader>hR', gitsigns.reset_buffer, '[H]unk [R]eset buffer')
      map('n', '<leader>hp', gitsigns.preview_hunk, '[H]unk [P]review')
      map('n', '<leader>hb', function()
        gitsigns.blame_line { full = true }
      end, '[H]unk [B]lame line')
      map('n', '<leader>hd', gitsigns.diffthis, '[H]unk [D]iff this')
      map('n', '<leader>hD', function()
        gitsigns.diffthis '~'
      end, '[H]unk [D]iff this against previous')
      map('n', '<leader>tb', gitsigns.toggle_current_line_blame, '[T]oggle line [B]lame')
      map('n', '<leader>tw', gitsigns.toggle_word_diff, '[T]oggle [W]ord diff')
    end,
  },
}
