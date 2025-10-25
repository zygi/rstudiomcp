# CLAUDE.md - Developer Notes for AI Assistants

## What This Is
MCP (Model Context Protocol) server for RStudio. Allows Claude Code to interact with active RStudio sessions via httpuv server on localhost.

## Critical Architecture Points

### Server Lifecycle & devtools::load_all()
- **Problem**: `devtools::load_all(reset=TRUE)` does NOT call `.onUnload()`, only `.onDetach()`
- **Solution**: Server cleanup happens in `.onDetach()`, not `.onUnload()`
- **Persistent reference**: Server object stored in `.GlobalEnv` as `.rstudiomcp_server` to survive namespace reloads
- **Security**: `.onDetach()` ONLY stops servers we created (via persistent ref). Never arbitrarily stop servers from `httpuv::listServers()`

### Server Binding
- Uses `127.0.0.1` (localhost only), NOT `0.0.0.0` (security - no external network access)

### Package Environment
- Single environment `.rstudiomcp_env` holds all package state (server, port, SSE connections, viewer tracking)
- Finalizer attached to `.rstudiomcp_env` for cleanup on R session exit
- Isolated with `parent = emptyenv()` to avoid namespace pollution

### Auto-load System
- Project-level `.Rprofile` modification (not user-level)
- Opt-in via `setup_autoload()`, requires user confirmation
- `.onLoad()` checks `get_mcp_auto_start()` preference

### Tool Design Principles
- File operations: Use `file_path` to target specific open documents, defaults to active document
- `replace_text_range`: Exact string match, shows ±3 lines context
- `source_document`: Requires BOTH `doc_id` and `doc_name` for safety/clarity
- `eval_r`: Has `allow_reassign` param - only true if expecting to overwrite existing vars

### Process Killing (Fallback for Orphaned Servers)
- OS-level: Windows uses `cmd /c "netstat -ano | findstr :PORT"`, macOS/Linux uses `lsof -ti:PORT`
- **Safety**: Check if PID == current R process PID before killing (killing own process = crash)
- Must wrap Windows commands in `cmd /c` for pipes to work in `system()`

### Testing
- `kill_process_on_port()` test creates httpuv server, verifies OS detection works
- Tests use random high ports (30000-50000) to avoid conflicts

## Common Pitfalls
1. **Empty JSON objects**: Use `names(obj) <- character(0)`, NOT just `list()` (becomes array `[]` not object `{}`)
2. **setNames() in .onLoad()**: Not available during early package load - use explicit name assignment
3. **httpuv::listServers()**: Only shows servers in current session, not across namespace reloads - use persistent ref
4. **Interactive prompts**: `readline()` only works if `interactive() == TRUE`

## Files to Know
- `R/zzz.R`: `.onLoad()`, `.onDetach()`, `.onUnload()` hooks
- `R/mcp_server.R`: Main server, tool definitions, persistent ref system
- `R/settings.R`: Preferences (port, auto-start), `.Rprofile` manipulation
- `R/mcp_config.R`: `.mcp.json` file management for Claude Code config
- `inst/rstudio/addins.dcf`: RStudio addins menu items

## Debug Mode
All debug messages use `[DEBUG]` prefix - search/replace to remove for release.

## Server Instructions
Set in `handle_initialize()` result under `instructions` field. Appears in Claude Code's system prompt.
