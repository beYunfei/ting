local M = {}
local storage = require("ting.storage")
local config = require("ting.config")

local namespace_id = vim.api.nvim_create_namespace("ting")

-- Notification sidebar state
local notif = {
  buf = nil,
  win = nil,
  ns = vim.api.nvim_create_namespace("ting_notifs"),
}

local function ensure_notif_window()
  if notif.win and vim.api.nvim_win_is_valid(notif.win) and notif.buf and vim.api.nvim_buf_is_valid(notif.buf) then
    return
  end

  local width = math.max(30, math.floor(vim.o.columns * 0.25))
  local height = math.max(4, vim.o.lines - 2)

  notif.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(notif.buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(notif.buf, "modifiable", true)
  vim.api.nvim_buf_set_option(notif.buf, "filetype", "ting_notifications")

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = vim.o.columns - width,
    row = 0,
    style = "minimal",
    border = "rounded",
    focusable = false,
  }

  notif.win = vim.api.nvim_open_win(notif.buf, false, win_opts)
  vim.api.nvim_win_set_option(notif.win, "wrap", false)
  vim.api.nvim_win_set_option(notif.win, "number", false)
  vim.api.nvim_win_set_option(notif.win, "relativenumber", false)
end

-- Public: add a notification to the right-side panel
function M.notify(msg, level, opts)
  level = level or vim.log.levels.INFO
  opts = opts or {}
  ensure_notif_window()

  local lvl_name = "INFO"
  local hl = "DiagnosticInfo"
  if level == vim.log.levels.WARN then lvl_name = "WARN"; hl = "DiagnosticWarn" end
  if level == vim.log.levels.ERROR then lvl_name = "ERROR"; hl = "DiagnosticError" end

  local timestamp = os.date("%H:%M")
  local line = string.format("%s [%s] %s", timestamp, lvl_name, msg)

  local ok, _ = pcall(function()
    local cur = vim.api.nvim_buf_get_lines(notif.buf, 0, -1, false)
    table.insert(cur, line)
    vim.api.nvim_buf_set_lines(notif.buf, 0, -1, false, cur)
    local last = #cur
    vim.api.nvim_buf_add_highlight(notif.buf, notif.ns, hl, last - 1, 0, -1)
    pcall(vim.api.nvim_win_set_cursor, notif.win, {last, 0})
  end)

  if not ok then
    -- Fallback to notify if sidebar creation fails
    vim.notify(msg, level, opts)
  end
end

function M.clear_notifications()
  if notif.buf and vim.api.nvim_buf_is_valid(notif.buf) then
    vim.api.nvim_buf_set_lines(notif.buf, 0, -1, false, {})
  end
end

function M.refresh_marks(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then return end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace_id, 0, -1)

  local file_comments = storage.get_comments_for_file(file_path)
  for line_num_str, data in pairs(file_comments) do
    local line_num = tonumber(line_num_str)
    -- Extmarks are 0-indexed
    pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace_id, line_num - 1, 0, {
      sign_text = "💬",
      sign_hl_group = "DiagnosticInfo",
    })
  end
end

-- Opens floating window
function M.open_input_window()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]
  local context = vim.api.nvim_get_current_line()

  -- Check if comment already exists
  local existing_comment = storage.get_comment(file_path, line_num)
  local initial_text = existing_comment and existing_comment.comment or ""

  -- Create buffer
  local float_buf = vim.api.nvim_create_buf(false, true)
  if initial_text ~= "" then
    local lines = vim.split(initial_text, "\n")
    vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)
  end

  -- Calculate window size
  local width = math.floor(vim.o.columns * 0.5)
  local height = 5
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = existing_comment and " Edit Comment " or " New Comment ",
    title_pos = "center",
  }

  local float_win = vim.api.nvim_open_win(float_buf, true, win_opts)

  -- Function to confirm context
  local confirm_input = function()
    local lines = vim.api.nvim_buf_get_lines(float_buf, 0, -1, false)
    local comment_text = table.concat(lines, "\n")
    if vim.trim(comment_text) == "" then
      -- If empty, delete the comment
      storage.delete_comment(file_path, line_num)
      vim.api.nvim_win_close(float_win, true)
      M.refresh_marks(bufnr)
      M.notify("Comment deleted!", vim.log.levels.INFO, { title = "Ting" })
      return
    end

    storage.add_comment(file_path, line_num, context, comment_text)
    vim.api.nvim_win_close(float_win, true)
    M.refresh_marks(bufnr)
    M.notify("Comment saved!", vim.log.levels.INFO, { title = "Ting" })

    -- Trigger the review and planning workflow
    local agents = require("ting.agents")
    agents.trigger_review_and_plan(comment_text, file_path)
  end

  -- Function to cancel input
  local cancel_input = function()
    vim.api.nvim_win_close(float_win, true)
  end

  -- Function to delete input explicitly
  local delete_input = function()
    storage.delete_comment(file_path, line_num)
    vim.api.nvim_win_close(float_win, true)
    M.refresh_marks(bufnr)
    M.notify("Comment deleted!", vim.log.levels.INFO, { title = "Ting" })
  end

  -- Keymaps for floating buffer
  local map_opts = { noremap = true, silent = true, buffer = float_buf }
  vim.keymap.set({'i', 'n'}, config.options.keys.confirm_input, confirm_input, map_opts)
  vim.keymap.set({'i', 'n'}, config.options.keys.cancel_input, cancel_input, map_opts)

  if config.options.keys.delete_comment then
    vim.keymap.set({'i', 'n'}, config.options.keys.delete_comment, delete_input, map_opts)
  end

  -- Start in insert mode
  vim.cmd("startinsert")
end

-- Hover to see comment
local popup_win = nil
function M.show_hover_comment()
  local bufnr = vim.api.nvim_get_current_buf()
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_num = cursor[1]

  local existing_comment = storage.get_comment(file_path, line_num)

  -- close existing popup
  if popup_win and vim.api.nvim_win_is_valid(popup_win) then
    vim.api.nvim_win_close(popup_win, true)
    popup_win = nil
  end

  if not existing_comment then return end

  local lines = vim.split(existing_comment.comment, "\n")
  table.insert(lines, 1, "=== Comment (" .. existing_comment.datetime .. ") ===")
  table.insert(lines, 2, "")

  local float_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(float_buf, 0, -1, false, lines)

  local max_width = 50
  for _, line in ipairs(lines) do
    if #line > max_width then max_width = #line end
  end

  local win_opts = {
    relative = "cursor",
    width = max_width + 2,
    height = #lines,
    col = 1,
    row = 1,
    style = "minimal",
    border = "single",
    focusable = false,
  }

  popup_win = vim.api.nvim_open_win(float_buf, false, win_opts)

  -- Auto close popup on cursor move
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = bufnr,
    callback = function()
      if popup_win and vim.api.nvim_win_is_valid(popup_win) then
        vim.api.nvim_win_close(popup_win, true)
        popup_win = nil
      end
    end,
    once = true,
  })
end

return M
