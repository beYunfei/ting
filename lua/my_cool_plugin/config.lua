local M = {}

M.options = {
  workspace_dir = ".mor",
  comments_file = ".comments",
  ollama_url = "http://localhost:11434/api/generate",
  ollama_model = "llama3",
  keys = {
    add_comment = "<M-c>",
    tech_writer = "<M-d>",
    pm_agent = "<M-s>",
    confirm_input = "<M-s>",
    cancel_input = "<M-c>",
    delete_comment = "<M-x>",
  }
}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.options, opts or {})
end

return M
