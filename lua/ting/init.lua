local M = {}

local config = require("ting.config")
local ui = require("ting.ui")
local agents = require("ting.agents")

M.setup = function(opts)
  config.setup(opts)
  
  -- Set up keymaps
  local keys = config.options.keys
  vim.keymap.set('n', keys.add_comment, ui.open_input_window, { desc = "Open Plugin Comment Input" })
  vim.keymap.set('n', keys.tech_writer, agents.trigger_tech_writer, { desc = "Trigger Tech Writer Agent" })
  vim.keymap.set('n', keys.pm_agent, agents.trigger_pm_agent, { desc = "Trigger PM Agent" })
  
  -- Autocommands to refresh marks
  local group = vim.api.nvim_create_augroup("TingPluginGroup", { clear = true })
  
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
    group = group,
    callback = function(args)
      ui.refresh_marks(args.buf)
    end,
  })
  
  -- CursorHold for hover comment
  -- Reduce updatetime to make hover feel responsive, standard is 4000
  if vim.o.updatetime > 1000 then
    vim.o.updatetime = 500
  end
  vim.api.nvim_create_autocmd("CursorHold", {
    group = group,
    callback = function()
      ui.show_hover_comment()
    end,
  })
end

-- This allows the 'require' command to see our functions
return M
