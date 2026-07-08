local M = {}
local config = require("ting.config")

-- Safe notify helper: use sidebar UI if already loaded, otherwise fallback to vim.notify
local function safe_notify(msg, level, opts)
  local ui_mod = package.loaded["ting.ui"]
  if ui_mod and ui_mod.notify then
    ui_mod.notify(msg, level, opts)
  else
    vim.notify(msg, level, opts)
  end
end

function M.get_comments_path()
  local cwd = vim.fn.getcwd()
  return cwd .. "/" .. config.options.workspace_dir .. "/" .. config.options.comments_file
end

function M.load_comments()
  local path = M.get_comments_path()
  if vim.fn.filereadable(path) == 0 then
    return {}
  end

  local lines = vim.fn.readfile(path)
  if #lines == 0 then return {} end

  local json_str = table.concat(lines, "\n")
  local ok, decoded = pcall(vim.fn.json_decode, json_str)
  if not ok or not decoded then
    return {}
  end
  return decoded
end

function M.save_comments(comments)
  local path = M.get_comments_path()
  local dir = vim.fn.fnamemodify(path, ":h")

  -- DEBUG INFO
  safe_notify("Attempting to write to directory: " .. dir, vim.log.levels.INFO, { title = "Ting Debug" })

  if vim.fn.isdirectory(dir) == 0 then
    safe_notify("Directory does not exist. Creating it now...", vim.log.levels.WARN, { title = "Ting Debug" })
    vim.fn.mkdir(dir, "p")
  end

  local json_str = vim.fn.json_encode(comments)
  local success = vim.fn.writefile({json_str}, path)

  if success == -1 then
    safe_notify("CRITICAL ERROR: Failed to write comments to " .. path, vim.log.levels.ERROR, { title = "Ting" })
  else
    safe_notify("Successfully wrote file to disk at: " .. path, vim.log.levels.INFO, { title = "Ting Debug" })
  end
end

function M.add_comment(file_path, line_num, context, comment_text)
  local comments = M.load_comments()
  local rel_path = vim.fn.fnamemodify(file_path, ":~:.")

  if not comments[rel_path] then
    comments[rel_path] = {}
  end

  -- Replace or add comment for the specific line
  comments[rel_path][tostring(line_num)] = {
    context = context,
    comment = comment_text,
    datetime = os.date("%Y-%m-%dT%H:%M:%S")
  }

  M.save_comments(comments)
end

function M.delete_comment(file_path, line_num)
  local comments = M.load_comments()
  local rel_path = vim.fn.fnamemodify(file_path, ":~:.")

  if comments[rel_path] and comments[rel_path][tostring(line_num)] then
    comments[rel_path][tostring(line_num)] = nil
    if vim.tbl_isempty(comments[rel_path]) then
      comments[rel_path] = nil
    end
    M.save_comments(comments)
  end
end

function M.get_comment(file_path, line_num)
  local comments = M.load_comments()
  local rel_path = vim.fn.fnamemodify(file_path, ":~:.")
  if comments[rel_path] and comments[rel_path][tostring(line_num)] then
    return comments[rel_path][tostring(line_num)]
  end
  return nil
end

function M.get_comments_for_file(file_path)
  local comments = M.load_comments()
  local rel_path = vim.fn.fnamemodify(file_path, ":~:.")
  return comments[rel_path] or {}
end

return M
