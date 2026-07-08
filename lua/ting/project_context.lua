#!/usr/bin/env nvim -l
--- Project Context Dump
--- Run: nvim -l lua/ting/project_context.lua
--- Use the output as the /init prompt to regenerate AGENTS.md

local function dump()
  local parts = {
    [[
=============================================================================
 PROJECT: ting — Neovim LLM Code-Review Plugin
=============================================================================

## Core Concept

A Neovim plugin that lets users attach line-specific comments to any file,
then invoke LLM agents (via local Ollama) that process the file *together
with* those comments as context.

The key insight: every AI discussion is grounded in a specific document
and specific lines within it, narrowing the topic to a concrete scenario
instead of an abstract conversation.

## Current State (codebase reality)

The plugin is functional but minimal — a single-person MVP. Five Lua modules
in lua/ting/:

  init.lua     — entrypoint, sets up keymaps and autocommands
  config.lua   — defaults (ollama URL, model, keybindings)
  storage.lua  — reads/writes ".mor/.comments" JSON per cwd
  ui.lua       — floating comment input, hover popup, notification sidebar
  agents.lua   — async Ollama calls + external Python agent integration

Dependencies:
  - Neovim >= 0.9 (jobstart, nvim_open_win, nvim_create_autocmd)
  - lazy.nvim plugin manager
  - Ollama at http://localhost:11434 (default model: llama3)
  - Python agents at ~/ssd/17-AI-programma/mormor (separate project)

Also referenced: ~/Documents/04-proj/03-mormorAgents (another related project)

No tests. No CI. No lint/typecheck. No README.

=============================================================================
 UX VISION (Very Important — This Is a Big Work Area)
=============================================================================

## Current UX (minimal)

  - Floating input window: 50% width, 5 rows tall, plain text
  - Notification sidebar: right-side panel, shows timestamped log messages
  - Extmark signs: 💬 on commented lines
  - Hover popup: shows comment text at cursor on CursorHold

## UX Principles

  1. Every interaction should feel instant or show clear progress
  2. Keyboard-first (this is Neovim)
  3. Visual hierarchy: comments, agent output, status, errors
  4. Non-intrusive: stay out of the way until the user needs you
  5. Threaded: a comment at a line is the start of a conversation

## UX Areas That Need Work

### Comment Input
  - Syntax highlighting in the input window (markdown?)
  - Resizable or auto-growing input
  - Show line context visibly (not just captured silently)
  - Quick-edit existing comments (currently works but no live preview)
  - Multi-line with proper undo/redo in the float

### Comment Display
  - Threaded replies per line (not just a single comment)
  - Better rendering in hover popup (markdown formatting)
  - Collapsible threads
  - Visual indication of resolved/unresolved comments
  - Filter: show only unresolved, only mine, etc.

### Agent Interaction
  - Streaming output in diff buffer instead of waiting for full response
  - Agent status indicator (spinner or statusline segment)
  - Cancel in-flight agent requests
  - Richer diff display (word-level diff, side-by-side)
  - Accept/reject individual changes in the diff
  - History of agent runs per file

### Notification System
  - Current sidebar works but is fragile (no persistence, no scrollback limit)
  - Categories/filtering (errors vs info vs agent output)
  - Dismiss individual notifications
  - Inline progress bars for long-running operations

### Navigation
  - Jump between commented lines (]c / [c-style)
  - List all comments in a file (like :Trouble or :Telescope)
  - Global comment overview across project files
  - Quick-open agent output buffers

=============================================================================
 LLM PERFORMANCE (Also Very Important)
=============================================================================

## Current Approach

  - curl POST to Ollama /api/generate with stream=false
  - vim.fn.jobstart for async execution
  - No streaming, no progress, no timeout handling
  - Single model for all tasks

## Performance Considerations

### Streaming
  - stream=true in Ollama gives token-by-token response
  - Need to handle partial JSON lines (NDJSON)
  - Can update diff buffer incrementally for progressive output
  - Much better UX than waiting 10-30s for a full response

### Model Selection
  - Different tasks need different models:
    * Quick inline suggestions → small/fast (qwen2.5-coder:1.5b, phi)
    * Architecture review → large (qwen2.5-coder:14b, deepseek-coder)
    * PM agent chat → large (llama3, qwen2.5)
    * Code generation → code-specific (qwen2.5-coder, deepseek-coder)
  - User should be able to configure per-agent model
  - Graceful fallback if model unavailable

### Context Management
  - Large files + many comments can exceed context window
  - Strategy: truncate file content to fit, summarize, or chunk
  - Need to count tokens before sending (tiktoken or similar)
  - Sliding window over the file focused on commented regions

### Prompt Engineering
  - Current prompts are hardcoded in agents.lua
  - Should be user-configurable (agent 'system prompts')
  - Structured output parsing (code blocks, JSON, diffs)
  - Few-shot examples in prompts improve output quality significantly

### Caching
  - Same file + same comments = same response (cache key)
  - Invalidate cache when file or comments change
  - Disk cache in .mor/ directory

### Reliability
  - Network errors: retry with backoff
  - Timeouts: configurable per agent
  - Partial output detection (did the model stop mid-response?)
  - Logging for debugging prompt chains

=============================================================================
 WORKFLOW
=============================================================================

## Current Workflow

  1. User opens file, places cursor on a line
  2. Press M-c → floating input → type comment → M-s to save
  3. 💬 sign appears on commented line
  4. User can hover any line to see comment
  5. Press M-d → sends file + all comments to Ollama → opens vsplit with diff
  6. Press M-s again → opens PM agent chat buffer
  7. Saving a comment also calls external Python review_agent

## Intended / Future Workflow

### Phase: Comment
  - Place cursor, press binding → float appears with line context header
  - Type comment in markdown (bold, code, lists rendered in real time)
  - Submit → comment stored locally → extmark appears
  - Optionally triggers review agent automatically (configurable)
  - Hover to see, click to reply/thread

### Phase: Review
  - "Review this file with all comments" → choose agent or use default
  - Agent streams its analysis into a scratch buffer
  - Buffer is set up as a diff against the original file
  - User navigates suggested changes, accepts/rejects per hunk
  - Can iterate: "Make it more concise" → follow-up prompt in same session

### Phase: Chat
  - Named PM / Architect / Tech Lead agents with custom system prompts
  - Chat buffer with markdown rendering
  - Slash commands: /summarize, /plan, /review, /ask
  - References to lines: /review lines 42-57

### Phase: Project
  - Global comment overview: all comments across all files
  - Agent run history: what changed, why, who approved
  - Export: generate markdown report of all comments + agent responses

=============================================================================
 EXTERNAL INTEGRATION — Python Agents
=============================================================================

  - Located at ~/ssd/17-AI-programma/mormor (or ~/Documents/04-proj/03-mormorAgents)
  - Called via: python3 -m agents.core.base_agent -p <project> --file <path> --comment <text>
  - Also: python3 -m agents.generators.tasks_gen -p <project> -a <arch> -o tasks_todo.md
  - These are called with jobstart, cwd set to the project dir
  - stdout is captured and interpreted as the agent response
  - No error recovery if python3 or the module is missing

  Issues:
  - Hardcoded path (users's home dir) — not portable
  - Should check if the external project exists before calling
  - Should handle the case where the Python env isn't set up
  - The external project might have its own dependencies (check its requirements.txt)

=============================================================================
 ARCHITECTURE & TECHNICAL DECISIONS
=============================================================================

## Plugin Structure

  - Standard Neovim Lua plugin layout
  - No luarocks / external Lua dependencies
  - Uses only built-in Neovim APIs + vim.fn
  - Plugin manager: lazy.nvim (bootstrapped in init.lua)

## Key Technical Decisions

  - Async via jobstart, not plenary or vim.uv directly
  - JSON persistence instead of vim.fn.sqlite or vim.fn.sql
  - curl for HTTP instead of vim.fn.system or plenary.curl
  - Floating windows via nvim_open_win (Neovim >= 0.9)

## Potential Improvements

  - Replace curl calls with a proper Neovim HTTP library or plenary
  - Use vim.uv for more control over async operations
  - neoconf / nvim-treesitter for markdown rendering in comments
  - Telescope integration for comment listing and navigation
  - Persist notification history (not just in-memory buffer)

=============================================================================
 CONSTRAINTS & GOTCHAS
=============================================================================

  1. Model must be pulled in Ollama before use — not handled by plugin
  2. Terminal emulators often steal M-c, M-s, M-x keybindings
  3. Notification sidebar breaks if window layout changes unexpectedly
  4. Comments are stored per-cwd, not per-project — relative path magic
  5. Python agent path is hardcoded — will break on other machines
  6. No tests — manual testing only
  7. cursorhold at 500ms may interfere with other plugins
  8. Debug notifications are noisy — user may want INFO-only mode
  9. The .mor directory is tracked by nothing — gets lost on git clean
  10. External Python project is the real "agent engine" — this plugin is the UI layer

=============================================================================
 KEY BINDINGS REFERENCE
=============================================================================

  Normal mode:
    <M-c>  Open/add comment at cursor line
    <M-d>  Trigger Technical Writer agent (full file review)
    <M-s>  Open PM Agent chat buffer
    <M-x>  Delete comment at cursor line

  Float window (insert & normal):
    <M-s>  Confirm / save comment
    <M-c>  Cancel / close float

=============================================================================
 OUTPUT FORMAT FOR AGENTS.md
=============================================================================

When generating AGENTS.md, produce a compact instruction file for future
OpenCode (or similar LLM coding agent) sessions. Every line should answer:
"Would an agent likely miss this without help?"

Include:
  - Exact key bindings and their effects
  - Architecture overview (which module does what)
  - External dependencies (Ollama, Python agents at specific paths)
  - Workflow steps (comment → review → chat)
  - Dev notes (Neovim version, plugin manager, no tests/CI)
  - Gotchas (terminal keybinding conflicts, Python path, model availability)

Exclude:
  - Generic Lua/Neovim advice
  - Long tutorials
  - Obvious file listings
  - Speculative or unverifiable claims
]]
  }

  -- Read the actual source files and include their summaries
  local function get_file_info(path)
    local f = io.open(path, "r")
    if not f then return "  (file not found)" end
    local content = f:read("*all")
    f:close()
    local lines = {}
    for line in content:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
    return string.format("  %d lines, %d bytes", #lines, #content)
  end

  parts[#parts+1] = "\n## Source File Sizes\n"
  local src_path = debug.getinfo(1, "S").source
  src_path = src_path:gsub("^@", "")  -- nvim prefixes sourced files with @
  local src_dir = src_path:match("(.*/)") or "./lua/ting/"
  for _, name in ipairs({"init.lua", "config.lua", "storage.lua", "ui.lua", "agents.lua", "project_context.lua"}) do
    local path = src_dir .. name
    local info = get_file_info(path)
    parts[#parts+1] = string.format("  %-30s %s", name, info)
  end

  parts[#parts+1] = "\n## Directory Tree\n"
  local handle = io.popen("find " .. src_dir .. " -type f -not -path '*/.git/*' | sort 2>/dev/null || echo '(unavailable)'")
  if handle then
    parts[#parts+1] = handle:read("*a")
    handle:close()
  end

  print(table.concat(parts, "\n"))
end

dump()
