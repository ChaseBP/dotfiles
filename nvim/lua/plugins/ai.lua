return {
  {
    'zbirenbaum/copilot.lua',
    cmd = 'Copilot',
    event = 'InsertEnter',
    opts = {
      suggestion = { enabled = false },
      panel = { enabled = false },
      filetypes = {
        yaml = true,
        markdown = true,
        gitcommit = false,
        gitrebase = false,
        help = false,
        ['.'] = false,
        ['*'] = true,
      },
    },
  },
}
