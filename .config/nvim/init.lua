-- Starter config (no plugins). Neovim 0.12+

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local o = vim.opt

-- UI
o.number = true
o.relativenumber = true
o.cursorline = true
o.signcolumn = "yes"
o.termguicolors = false -- use the terminal's ANSI palette so Ghostty's theme drives colors
o.scrolloff = 8
o.wrap = false
o.splitright = true
o.splitbelow = true
o.showmode = false

-- Editing
o.expandtab = true
o.shiftwidth = 2
o.tabstop = 2
o.smartindent = true
o.undofile = true
o.swapfile = false
o.clipboard = "unnamedplus"
o.mouse = "a"

-- Search
o.ignorecase = true
o.smartcase = true
o.hlsearch = true
o.inccommand = "split"

-- Responsiveness
o.updatetime = 250
o.timeoutlen = 400

-- Keymaps
local map = vim.keymap.set

map("n", "<Esc>", "<cmd>nohlsearch<CR>")
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Save" })
map("n", "<leader>q", "<cmd>quit<CR>", { desc = "Quit" })

-- Window navigation
map("n", "<C-h>", "<C-w>h")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")
map("n", "<C-l>", "<C-w>l")

-- Keep selection when indenting
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Move selected lines
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

-- Diagnostics
map("n", "[d", function() vim.diagnostic.jump({ count = -1 }) end)
map("n", "]d", function() vim.diagnostic.jump({ count = 1 }) end)
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Line diagnostics" })

-- Autocommands
local group = vim.api.nvim_create_augroup("user", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = group,
  callback = function() vim.hl.on_yank() end,
})

-- Restore last cursor position
vim.api.nvim_create_autocmd("BufReadPost", {
  group = group,
  callback = function(ev)
    local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
    if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(ev.buf) then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- Colors: ANSI-only highlights, so they follow Ghostty's theme (including
-- light/dark switching) with no reload. Background stays transparent.
local function apply_highlights()
  local hl = function(name, val) vim.api.nvim_set_hl(0, name, val) end
  local c = function(fg, extra)
    return vim.tbl_extend("force", { ctermfg = fg, ctermbg = "NONE" }, extra or {})
  end
  for _, g in ipairs({ "Normal", "NormalFloat", "SignColumn", "EndOfBuffer", "FoldColumn" }) do
    hl(g, { ctermfg = "NONE", ctermbg = "NONE" })
  end
  hl("Comment", c(8, { italic = true }))
  hl("Constant", c(3))
  hl("String", c(2))
  hl("Number", c(3))
  hl("Identifier", c(6))
  hl("Function", c(4))
  hl("Statement", c(5))
  hl("PreProc", c(5))
  hl("Type", c(3))
  hl("Special", c(6))
  hl("Error", c(1, { bold = true }))
  hl("Todo", c(5, { bold = true }))
  hl("LineNr", c(8))
  hl("CursorLineNr", c(7, { bold = true }))
  hl("CursorLine", { ctermbg = "NONE" })
  hl("Visual", { ctermbg = 8, ctermfg = "NONE" })
  hl("Search", { ctermbg = 3, ctermfg = 0 })
  hl("IncSearch", { ctermbg = 5, ctermfg = 0 })
  hl("Pmenu", { ctermbg = 0, ctermfg = 7 })
  hl("PmenuSel", { ctermbg = 8, ctermfg = 15 })
  hl("StatusLine", { ctermbg = 0, ctermfg = 7 })
  hl("StatusLineNC", { ctermbg = 0, ctermfg = 8 })
  hl("WinSeparator", c(8))
  hl("MatchParen", { bold = true, underline = true })
  hl("DiagnosticError", c(1))
  hl("DiagnosticWarn", c(3))
  hl("DiagnosticInfo", c(4))
  hl("DiagnosticHint", c(6))
end

vim.api.nvim_create_autocmd({ "ColorScheme", "VimEnter" }, { group = group, callback = apply_highlights })
apply_highlights()
