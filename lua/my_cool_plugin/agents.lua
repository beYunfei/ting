local M = {}
local storage = require("my_cool_plugin.storage")
local config = require("my_cool_plugin.config")
local ui = require("my_cool_plugin.ui")

-- Helper to make asynchronous curl requests to Ollama
local function query_ollama(prompt, callback)
  local url = config.options.ollama_url
  local user_model = config.options.ollama_model

  local payload = vim.fn.json_encode({
    model = user_model,
    prompt = prompt,
    stream = false
  })

  local cmd = {
    "curl",
    "-s",
    "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", payload,
    url
  }

  ui.notify("Running jobstart: " .. vim.inspect(cmd), vim.log.levels.INFO, { title = "Ollama" })
  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local json_str = table.concat(data, "\n")
        ui.notify("Ollama stdout: " .. json_str, vim.log.levels.INFO, { title = "Ollama" })
        if json_str ~= "" then
          local ok, decoded = pcall(vim.fn.json_decode, json_str)
          if ok and decoded and decoded.response then
            callback(decoded.response)
          else
            callback("Error parsing Ollama response: " .. json_str)
          end
        end
      end
    end,
    on_stderr = function(_, err)
      if err and err[1] ~= "" then
        ui.notify("Ollama stderr: " .. table.concat(err, "\n"), vim.log.levels.ERROR, { title = "Ollama" })
      end
    end,
  })
end

function M.trigger_tech_writer()
  local file_path = vim.api.nvim_buf_get_name(0)
  local comments = storage.get_comments_for_file(file_path)

  if vim.tbl_isempty(comments) then
    ui.notify("No comments found for this file. Add comments to trigger the Technical Writer agent.", vim.log.levels.WARN, { title = "My Plugin" })
    return
  end

  local file_content = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

  local prompt = "You are an expert Technical Writer Agent.\n"
  prompt = prompt .. "Review the following file and incorporate the user's comments to propose a revised version of the file.\n\n"
  prompt = prompt .. "Comments:\n"
  for line, data in pairs(comments) do
     prompt = prompt .. "- Line " .. line .. " (Context: " .. data.context .. "): " .. data.comment .. "\n"
  end
  prompt = prompt .. "\nFile Content:\n" .. file_content
  prompt = prompt .. "\n\nPlease output ONLY the raw updated file content. Do not include markdown blocks or any other text. I just want the code."

  ui.notify("Triggering Technical Writer Agent for " .. vim.fn.expand("%:t") .. " via Ollama...", vim.log.levels.INFO, { title = "My Plugin" })

  query_ollama(prompt, function(response)
    vim.schedule(function()
      local diff_buf = vim.api.nvim_create_buf(false, true)
      local cleaned_response = response:gsub("^```%w*\n", ""):gsub("```$", "")
      vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, vim.split(cleaned_response, "\n"))

      -- Open in split
      vim.cmd("vsplit")
      vim.api.nvim_win_set_buf(0, diff_buf)
      vim.cmd("diffthis")
      vim.cmd("wincmd p")
      vim.cmd("diffthis")

      ui.notify("Review the proposed changes in the diff split.", vim.log.levels.INFO, { title = "Tech Writer" })
    end)
  end)
end

function M.trigger_pm_agent()
  ui.notify("Opening PM Agent chat...", vim.log.levels.INFO, { title = "My Plugin" })

  vim.cmd("split")
  local chat_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, chat_buf)

  local welcome_msg = {
    "-- PM Agent Chat Environment --",
    "-- Type your question below and save (`:w`) to send context to Ollama --",
    ""
  }
  vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, welcome_msg)

  -- Create Buffer write autocommand to trigger Ollama
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = chat_buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
      local user_input = table.concat(lines, "\n")

      local prompt = "You are an expert Product Manager Agent guiding a software engineer.\n"
      prompt = prompt .. "Answer the following question from the engineer based on their current context:\n\n"
      prompt = prompt .. user_input

      ui.notify("Thinking...", vim.log.levels.INFO, { title = "PM Agent" })

      query_ollama(prompt, function(response)
        vim.schedule(function()
          local current_lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
          table.insert(current_lines, "")
          table.insert(current_lines, "--- PM Agent Reply ---")
          for _, r_line in ipairs(vim.split(response, "\n")) do
             table.insert(current_lines, r_line)
          end
          table.insert(current_lines, "----------------------")
          table.insert(current_lines, "")
          vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, current_lines)
          -- Move cursor to bottom
          vim.api.nvim_win_set_cursor(0, { #current_lines, 0 })
          ui.notify("Done.", vim.log.levels.INFO, { title = "PM Agent" })
        end)
      end)

      -- Mark as saved
      vim.api.nvim_set_option_value("modified", false, { buf = chat_buf })
    end
  })

  vim.cmd("startinsert!")
end

function M.confirm_task(buf, project_dir, old_win)
  local lines = vim.api.nvim_buf_get_lines(buf, 3, -1, false) -- skip the header
  local content = table.concat(lines, "\n")

  local pdir = project_dir .. "/.mormor"
  if vim.fn.isdirectory(pdir) == 0 then
    vim.fn.mkdir(pdir, "p")
  end

  local temp_file = pdir .. "/temp_architecture.md"
  vim.fn.writefile(vim.split(content, "\n"), temp_file)

  ui.notify("Generating detailed tasks_todo.md... (cmd: " .. vim.inspect(cmd) .. ")", vim.log.levels.INFO, { title = "My Plugin" })

  local cmd = {
    "python3",
    "-m", "agents.generators.tasks_gen",
    "-p", project_dir,
    "-a", temp_file,
    "-o", "tasks_todo.md"
  }

  vim.fn.jobstart(cmd, {
    cwd = project_dir,
    stdout_buffered = true,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          local tasks_file = project_dir .. "/tasks_todo.md"
          -- reuse the existing window to show tasks_todo.md
          if vim.api.nvim_win_is_valid(old_win) then
            vim.api.nvim_win_set_buf(old_win, vim.fn.bufadd(tasks_file))
            vim.api.nvim_win_call(old_win, function() vim.cmd("edit!") end)
          else
            vim.cmd("vsplit " .. tasks_file)
          end
          ui.notify("Generated tasks_todo.md successfully! (exit=" .. tostring(code) .. ")", vim.log.levels.INFO, { title = "My Plugin" })
        else
          ui.notify("Failed to generate tasks. (exit=" .. tostring(code) .. ")", vim.log.levels.ERROR, { title = "My Plugin" })
        end
      end)
    end,
    on_stderr = function(_, err)
      if err and err[1] ~= "" then
        ui.notify("Tasks Generator stderr: " .. table.concat(err, "\n"), vim.log.levels.ERROR, { title = "My Plugin" })
      end
    end
  })
end

function M.show_proposed_task(content, project_dir)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(content, "\n")

  -- Add instructions at the top
  table.insert(lines, 1, "=== Proposed Task (by review_agent) ===")
  table.insert(lines, 2, "=== Press <CR> in normal mode to confirm and generate tasks ===")
  table.insert(lines, 3, "")

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  -- Set keymap to confirm
  vim.keymap.set('n', '<CR>', function()
    M.confirm_task(buf, project_dir, win)
  end, { buffer = buf, noremap = true, silent = true, desc = "Confirm task and generate tasks_todo.md" })
end

function M.trigger_review_and_plan(comment_text, file_path)
  local project_dir = vim.fn.expand("~/ssd/17-AI-programma/mormor")

  ui.notify("Reviewing code and proposing task... (cmd: " .. vim.inspect(cmd) .. ")", vim.log.levels.INFO, { title = "My Plugin" })

  local cmd = {
    "python3",
    "-m", "agents.core.base_agent",
    "-p", project_dir,
    "--file", file_path,
    "--comment", comment_text
  }

  ui.notify("Running jobstart: " .. vim.inspect(cmd), vim.log.levels.INFO, { title = "Review Agent" })
  vim.fn.jobstart(cmd, {
    cwd = project_dir,
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data and #data > 0 then
        local output_str = table.concat(data, "\n")
        ui.notify("Review Agent stdout: " .. output_str, vim.log.levels.INFO, { title = "Review Agent" })
        if vim.trim(output_str) ~= "" then
          vim.schedule(function()
            M.show_proposed_task(output_str, project_dir)
          end)
        end
      end
    end,
    on_stderr = function(_, err)
      if err and err[1] ~= "" then
        ui.notify("Review Agent stderr: " .. table.concat(err, "\n"), vim.log.levels.ERROR, { title = "Review Agent" })
      end
    end
  })
end

return M
