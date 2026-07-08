# Ting

A Neovim plugin that grounds LLM discussions in specific lines of a document. Attach comments to lines, then invoke agents (via Ollama) that process the file together with those comments as context.

## Requirements

- Neovim >= 0.9 (`vim.fn.jobstart`, `nvim_open_win`, `nvim_create_autocmd`)
- [Ollama](https://ollama.ai) running at `http://localhost:11434` with at least one model pulled (default: `llama3`)

## Installation

This repo is a Neovim config directory. Ting lives at `lua/ting/` and is loaded from `init.lua`:

```lua
require("ting").setup()
```

With lazy.nvim (already bootstrapped in `init.lua`):

```lua
{
  dir = "~/path/to/this/repo/lua/ting",
  config = function() require("ting").setup() end,
}
```

## Configuration

```lua
require("ting").setup({
  workspace_dir = ".mor",       -- directory for comment storage
  comments_file = ".comments",   -- filename within workspace_dir
  ollama_url = "http://localhost:11434/api/generate",
  ollama_model = "llama3",
  keys = {
    add_comment = "<M-c>",
    tech_writer = "<M-d>",
    pm_agent = "<M-s>",
    delete_comment = "<M-x>",
  },
})
```

## Key Bindings

| Binding | Mode | Action |
|---------|------|--------|
| `<M-c>` | Normal | Open comment input at cursor line |
| `<M-d>` | Normal | Trigger Technical Writer agent (file + comments → Ollama → diff split) |
| `<M-s>` | Normal | Open PM Agent chat buffer |
| `<M-x>` | Normal | Delete comment at cursor line |
| `<M-s>` | Float | Confirm / save comment |
| `<M-c>` | Float | Cancel / close float |

> Terminal emulators often capture M-c / M-s / M-x. Remap in `config.options.keys` if needed.

## Usage

1. Open a file, place cursor on a line, press `<M-c>`
2. Type a comment in the floating window, press `<M-s>` to save — a 💬 sign appears
3. Hover any 💬 line to see the comment popup
4. Press `<M-d>` to send the file + all comments to Ollama — opens a `:diffthis` split with the proposed rewrite
5. Press `<M-s>` to open the PM Agent chat — type a question and `:w` to send

Saving a comment also triggers the external Python review agent (see below).

## How It Works

- Comments are stored as JSON in `.mor/.comments` relative to the current working directory
- Each comment records the line number, line context, timestamp, and comment text
- Extmarks (💬) are refreshed on `BufEnter` / `BufWritePost`
- Ollama calls run asynchronously via `vim.fn.jobstart` + `curl`
- Agent responses that produce code open in a vertical diff split for review

## External Python Agents

Ting integrates with a separate Python project at `~/ssd/17-AI-programma/mormor`:

- **`agents.core.base_agent`** — review + plan workflow, called automatically when a comment is saved
- **`agents.generators.tasks_gen`** — generates `tasks_todo.md` from proposed architecture

These are called via `jobstart` with the project dir as `cwd`. The path is currently hardcoded.

## Architecture

```
lua/ting/
  init.lua     — entrypoint, registers keymaps and autocommands
  config.lua   — defaults and user options
  storage.lua  — read/write comment JSON files
  ui.lua       — floating input window, hover popup, notification sidebar, extmark signs
  agents.lua   — async Ollama calls + external Python agent integration
```

## License

MIT
