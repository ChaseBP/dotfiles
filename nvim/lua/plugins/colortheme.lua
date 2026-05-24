local default_theme = 'rose-pine-main'
local state_file = vim.fn.stdpath 'state' .. '/colorscheme'

local transparency_enabled = false

local function setup_rose_pine(variant)
  require('rose-pine').setup {
    variant = variant,
    dark_variant = 'moon',
    dim_inactive_windows = false,
    extend_background_behind_borders = true,

    enable = {
      terminal = true,
      legacy_highlights = true,
      migrations = true,
    },

    styles = {
      bold = true,
      italic = true,
      transparency = transparency_enabled,
    },

    groups = {
      border = 'muted',
      link = 'iris',
      panel = 'surface',

      error = 'love',
      hint = 'iris',
      info = 'foam',
      note = 'pine',
      todo = 'rose',
      warn = 'gold',

      git_add = 'foam',
      git_change = 'rose',
      git_delete = 'love',
      git_dirty = 'rose',
      git_ignore = 'muted',
      git_merge = 'iris',
      git_rename = 'pine',
      git_stage = 'iris',
      git_text = 'rose',
      git_untracked = 'subtle',

      h1 = 'iris',
      h2 = 'foam',
      h3 = 'rose',
      h4 = 'gold',
      h5 = 'pine',
      h6 = 'foam',
    },

    highlight_groups = {
      TelescopeBorder = { fg = 'muted', bg = 'none' },
      FloatBorder = { fg = 'muted', bg = 'none' },
      WinSeparator = { fg = 'muted', bg = 'none' },
    },
  }
end

local function setup_kanagawa(variant)
  require('kanagawa').setup {
    compile = false,
    undercurl = true,
    commentStyle = { italic = true },
    functionStyle = { bold = false },
    keywordStyle = { italic = true },
    statementStyle = { bold = true },
    typeStyle = {},
    transparent = transparency_enabled,
    dimInactive = false,
    terminalColors = true,
    theme = variant,
    background = {
      dark = 'wave',
      light = 'lotus',
    },
    colors = {
      theme = {
        all = {
          ui = {
            bg_gutter = 'none',
            float = { bg = 'none', bg_border = 'none' },
          },
        },
      },
    },
    overrides = function(colors)
      local palette = colors.palette

      return {
        FloatBorder = { fg = palette.fujiGray, bg = 'none' },
        NormalFloat = { bg = transparency_enabled and 'none' or palette.sumiInk1 },
        TelescopeBorder = { fg = palette.fujiGray, bg = 'none' },
        WinSeparator = { fg = palette.fujiGray, bg = 'none' },
        DiagnosticError = { fg = palette.samuraiRed },
        DiagnosticWarn = { fg = palette.roninYellow },
        DiagnosticInfo = { fg = palette.waveAqua1 },
        DiagnosticHint = { fg = palette.springViolet1 },
        GitSignsAdd = { fg = palette.springGreen },
        GitSignsChange = { fg = palette.carpYellow },
        GitSignsDelete = { fg = palette.samuraiRed },
      }
    end,
  }
end

local function setup_tokyonight(variant)
  require('tokyonight').setup {
    style = variant,
    light_style = 'day',
    transparent = transparency_enabled,
    terminal_colors = true,
    styles = {
      comments = { italic = true },
      keywords = { italic = true },
      functions = {},
      variables = {},
      sidebars = transparency_enabled and 'transparent' or 'dark',
      floats = transparency_enabled and 'transparent' or 'dark',
    },
    sidebars = { 'qf', 'help', 'neo-tree', 'trouble' },
    day_brightness = 0.3,
    hide_inactive_statusline = false,
    dim_inactive = false,
    lualine_bold = true,
    on_highlights = function(hl, colors)
      hl.FloatBorder = { fg = colors.border_highlight, bg = 'none' }
      hl.NormalFloat = { bg = transparency_enabled and 'none' or colors.bg_float }
      hl.TelescopeBorder = { fg = colors.border_highlight, bg = 'none' }
      hl.WinSeparator = { fg = colors.border, bg = 'none' }
      hl.GitSignsAdd = { fg = colors.git.add }
      hl.GitSignsChange = { fg = colors.git.change }
      hl.GitSignsDelete = { fg = colors.git.delete }
    end,
  }
end

local theme_families = {
  {
    name = 'rose-pine',
    label = 'Rose Pine',
    variants = { 'main', 'moon', 'dawn' },
    setup = setup_rose_pine,
  },
  {
    name = 'kanagawa',
    label = 'Kanagawa',
    variants = { 'wave', 'dragon', 'lotus' },
    setup = setup_kanagawa,
  },
  {
    name = 'tokyonight',
    label = 'Tokyo Night',
    variants = { 'night', 'storm', 'moon', 'day' },
    setup = setup_tokyonight,
  },
}

local themes = {}

for _, family in ipairs(theme_families) do
  for _, variant in ipairs(family.variants) do
    local theme_family = family
    local theme_variant = variant

    themes[#themes + 1] = {
      name = ('%s-%s'):format(theme_family.name, theme_variant),
      family = theme_family.name,
      label = ('%s - %s'):format(theme_family.label, theme_variant:gsub('^%l', string.upper)),
      variant = theme_variant,
      colorscheme = ('%s-%s'):format(theme_family.name, theme_variant),
      setup = function()
        theme_family.setup(theme_variant)
      end,
    }
  end
end

local theme_by_name = {}

for index, theme in ipairs(themes) do
  theme.index = index
  theme_by_name[theme.name] = theme
end

local theme_aliases = {
  ['rose-pine'] = 'rose-pine-main',
  kanagawa = 'kanagawa-wave',
  tokyonight = 'tokyonight-night',
}

local function normalize_theme_name(name)
  return theme_aliases[name] or name
end

local function read_persisted_theme()
  local file = io.open(state_file, 'r')

  if not file then
    return nil
  end

  local name = vim.trim(file:read '*a')
  file:close()
  name = normalize_theme_name(name)

  if theme_by_name[name] then
    return name
  end

  return nil
end

local function persist_theme(name)
  vim.fn.mkdir(vim.fn.fnamemodify(state_file, ':h'), 'p')

  local file = io.open(state_file, 'w')

  if not file then
    vim.notify('Unable to persist colorscheme selection', vim.log.levels.WARN)
    return
  end

  file:write(name)
  file:close()
end

local function clear_transparent_backgrounds()
  local groups = {
    'Normal',
    'NormalNC',
    'NormalFloat',
    'FloatBorder',
    'SignColumn',
    'StatusLine',
    'StatusLineNC',
    'TabLine',
    'TabLineFill',
    'WinBar',
    'WinBarNC',
    'WinSeparator',
  }

  for _, group in ipairs(groups) do
    vim.api.nvim_set_hl(0, group, { bg = 'none' })
  end
end

local function apply_theme(name, opts)
  opts = opts or {}
  name = normalize_theme_name(name)

  local theme = theme_by_name[name] or theme_by_name[default_theme]

  theme.setup()

  local ok, err = pcall(vim.cmd.colorscheme, theme.colorscheme)

  if not ok then
    vim.notify(('Failed to apply colorscheme %s: %s'):format(theme.colorscheme, err), vim.log.levels.ERROR)
    return
  end

  if transparency_enabled then
    clear_transparent_backgrounds()
  end

  vim.g.colortheme = theme.name

  if opts.persist ~= false then
    persist_theme(theme.name)
  end

  if opts.notify ~= false then
    vim.notify(('Colorscheme: %s'):format(theme.label))
  end
end

local function selected_theme()
  return normalize_theme_name(vim.g.colortheme or read_persisted_theme() or default_theme)
end

local function cycle_theme()
  local current = theme_by_name[vim.g.colortheme] or theme_by_name[selected_theme()] or theme_by_name[default_theme]
  local next_theme = themes[(current.index % #themes) + 1]

  apply_theme(next_theme.name)
end

local function select_theme_with_telescope()
  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local conf = require('telescope.config').values
  local original_theme = selected_theme()
  local previewed_theme = original_theme

  local function preview_selection()
    local selection = action_state.get_selected_entry()

    if selection and selection.value.name ~= previewed_theme then
      previewed_theme = selection.value.name
      apply_theme(previewed_theme, { notify = false, persist = false })
    end
  end

  pickers
    .new({}, {
      prompt_title = 'Colorschemes',
      finder = finders.new_table {
        results = themes,
        entry_maker = function(theme)
          local active = theme.name == selected_theme()

          return {
            value = theme,
            display = ('%s%s'):format(active and '* ' or '  ', theme.label),
            ordinal = theme.name .. ' ' .. theme.label,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        local move_selection = function(action)
          action(prompt_bufnr)
          vim.schedule(preview_selection)
        end

        local restore_and_close = function()
          if previewed_theme ~= original_theme then
            apply_theme(original_theme, { notify = false, persist = false })
          end

          actions.close(prompt_bufnr)
        end

        map({ 'i', 'n' }, '<C-n>', function()
          move_selection(actions.move_selection_next)
        end)
        map({ 'i', 'n' }, '<Down>', function()
          move_selection(actions.move_selection_next)
        end)
        map({ 'i', 'n' }, '<C-p>', function()
          move_selection(actions.move_selection_previous)
        end)
        map({ 'i', 'n' }, '<Up>', function()
          move_selection(actions.move_selection_previous)
        end)
        map('n', 'j', function()
          move_selection(actions.move_selection_next)
        end)
        map('n', 'k', function()
          move_selection(actions.move_selection_previous)
        end)
        map({ 'i', 'n' }, '<Esc>', restore_and_close)
        map({ 'i', 'n' }, '<C-c>', restore_and_close)
        map('n', 'q', restore_and_close)

        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()

          actions.close(prompt_bufnr)

          if selection then
            apply_theme(selection.value.name)
          end
        end)

        return true
      end,
    })
    :find()
end

local function toggle_transparency()
  transparency_enabled = not transparency_enabled
  apply_theme(selected_theme(), { notify = false })
  vim.notify(('Background transparency: %s'):format(transparency_enabled and 'on' or 'off'))
end

return {
  'rose-pine/neovim',
  name = 'rose-pine',
  priority = 1000,
  dependencies = {
    'rebelot/kanagawa.nvim',
    'folke/tokyonight.nvim',
    'nvim-telescope/telescope.nvim',
  },
  config = function()
    vim.api.nvim_create_user_command('ColorThemeCycle', cycle_theme, { desc = 'Cycle colorschemes' })
    vim.api.nvim_create_user_command('ColorThemePicker', select_theme_with_telescope, { desc = 'Pick a colorscheme' })
    vim.api.nvim_create_user_command('ColorThemeSelect', function(args)
      apply_theme(args.args)
    end, {
      complete = function()
        return vim.tbl_map(function(theme)
          return theme.name
        end, themes)
      end,
      desc = 'Select a colorscheme',
      nargs = 1,
    })
    vim.api.nvim_create_user_command('ColorThemeToggleTransparency', toggle_transparency, { desc = 'Toggle background transparency' })

    vim.keymap.set('n', '<leader>bg', toggle_transparency, { desc = 'Toggle background transparency', noremap = true, silent = true })
    vim.keymap.set('n', '<leader>cs', select_theme_with_telescope, { desc = '[C]olor[S]cheme picker', noremap = true, silent = true })

    apply_theme(selected_theme(), { notify = false, persist = false })
  end,
}
