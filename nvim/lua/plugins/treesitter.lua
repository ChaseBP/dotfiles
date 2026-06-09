return {
  {
    'nvim-treesitter/nvim-treesitter',
    -- The legacy `master` branch is archived and incompatible with Neovim
    -- 0.11+ (its query predicates break injection parsing — e.g. markdown
    -- fenced code blocks). `main` is the rewrite for Neovim 0.11/0.12.
    branch = 'main',
    lazy = false, -- the main branch does not support lazy-loading
    build = ':TSUpdate',
    config = function()
      -- ── Stale-parser cleanup ─────────────────────────────────────────
      -- The `main` branch compiles parsers into stdpath('data')/site/parser,
      -- NOT the plugin's own parser/ directory.  Any .so files inside the
      -- plugin dir are leftovers from the archived `master` branch and will
      -- shadow Neovim 0.12's bundled parsers, producing ABI / query
      -- mismatches (e.g. "Invalid field name" errors).
      -- Remove them on every startup — the check is essentially free once
      -- the directory is already clean.
      local plugin_parser_dir = vim.fs.joinpath(
        vim.fn.stdpath('data') --[[@as string]],
        'lazy', 'nvim-treesitter', 'parser'
      )
      local plugin_info_dir = vim.fs.joinpath(
        vim.fn.stdpath('data') --[[@as string]],
        'lazy', 'nvim-treesitter', 'parser-info'
      )

      local cleaned = 0
      for _, dir in ipairs { plugin_parser_dir, plugin_info_dir } do
        if vim.fn.isdirectory(dir) == 1 then
          for name, ftype in vim.fs.dir(dir) do
            if ftype == 'file' and (name:match('%.so$') or name:match('%.revision$')) then
              os.remove(vim.fs.joinpath(dir, name))
              cleaned = cleaned + 1
            end
          end
        end
      end
      if cleaned > 0 then
        vim.notify(
          ('nvim-treesitter: cleaned %d stale file(s) from plugin dir'):format(cleaned),
          vim.log.levels.INFO
        )
      end

      require('nvim-treesitter').setup()

      -- ── Auto-install wanted parsers ──────────────────────────────────
      -- For the languages Neovim 0.12 bundles (c, lua, markdown,
      -- markdown_inline, query, vim, vimdoc) the built-in parsers + queries
      -- work out of the box.  Everything else needs the tree-sitter CLI.
      local wanted = {
        'bash', 'c', 'cmake', 'css', 'dockerfile', 'git_config', 'git_rebase',
        'gitattributes', 'gitcommit', 'gitignore', 'go', 'graphql', 'groovy',
        'html', 'java', 'javascript', 'json', 'jsonc', 'lua', 'luadoc', 'make',
        'markdown', 'markdown_inline', 'python', 'query', 'regex', 'sql',
        'terraform', 'toml', 'tsx', 'typescript', 'vim', 'vimdoc', 'yaml',
      }

      if vim.fn.executable 'tree-sitter' == 1 then
        -- Parsers already compiled via :TSUpdate / :TSInstall
        local have = {}
        for _, p in ipairs(require('nvim-treesitter').get_installed 'parsers') do
          have[p] = true
        end

        -- Parsers that Neovim ships — no need to recompile these
        local bundled = {}
        for _, path in ipairs(vim.api.nvim_get_runtime_file('parser/*.so', true)) do
          if not path:find('lazy') and not path:find('/site/') then
            bundled[vim.fn.fnamemodify(path, ':t:r')] = true
          end
        end

        local missing = vim.tbl_filter(function(p)
          return not have[p] and not bundled[p]
        end, wanted)
        if #missing > 0 then
          require('nvim-treesitter').install(missing)
        end
      end

      -- ── Per-buffer highlighting + indent ─────────────────────────────
      -- On the main branch these are no longer plugin "modules"; we enable
      -- them via vim.treesitter.start() and the plugin's indentexpr.
      local function enable(buf)
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        -- Skip special buffers (terminals, prompts, quickfix, …)
        if vim.bo[buf].buftype ~= '' then
          return
        end
        local ft = vim.bo[buf].filetype
        if ft == '' then
          return
        end
        local lang = vim.treesitter.language.get_lang(ft)
        if not lang then
          return
        end
        -- pcall: gracefully skip filetypes whose parser isn't available
        if pcall(vim.treesitter.start, buf, lang) then
          vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
        end
      end

      vim.api.nvim_create_autocmd('FileType', {
        group = vim.api.nvim_create_augroup('user_treesitter', { clear = true }),
        callback = function(args)
          enable(args.buf)
        end,
      })

      -- We load at startup (lazy=false), after the first file's FileType has
      -- already fired, so enable any buffers that are already open.
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          enable(buf)
        end
      end
    end,
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = { 'BufReadPost', 'BufNewFile' },
    dependencies = { 'nvim-treesitter/nvim-treesitter' },
    opts = {
      max_lines = 3,
      multiline_threshold = 1,
      trim_scope = 'outer',
      mode = 'cursor',
    },
    keys = {
      {
        '<leader>tc',
        function()
          require('treesitter-context').toggle()
        end,
        desc = '[T]oggle treesitter [C]ontext',
      },
    },
  },
}
