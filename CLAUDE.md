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
- Default port: 16751 (configurable via `configure_mcp_server()`)

### Package Environment
- Single environment `.rstudiomcp_env` holds all package state (server, port, SSE connections, viewer tracking)
- Finalizer attached to `.rstudiomcp_env` for cleanup on R session exit
- Isolated with `parent = emptyenv()` to avoid namespace pollution

### Package Dependencies
- Core: `jsonlite`, `httpuv`, `rstudioapi`
- UI: `shiny`, `miniUI`
- Utilities: `base64enc`, `glue`
- Dev: `roxygen2` (>= 7.3.3) for documentation generation

### Auto-load System
- Project-level `.Rprofile` modification (not user-level)
- Opt-in via `setup_autoload()`, requires user confirmation
- `.onLoad()` checks `get_mcp_auto_start()` preference

### Tool Design Principles

#### Document Operations (Active Document Model)
- **Core principle**: All document editing tools work ONLY on the currently active document
- **Tools affected**: `insert_text`, `replace_text_range`, `get_active_document`, `source_active_document`
- **Workflow**:
  1. To work with a document, first make it active using:
     - `create_document(text, path=None)` - creates new doc (saved or untitled), becomes active automatically
     - `open_document_file(file_path)` - opens/refocuses saved file
  2. Then use document tools on the now-active document
- **Why**: Aligns with rstudioapi's capabilities (see limitations below)

#### rstudioapi Document Limitations
- **Cannot list all open documents**: `getSourceEditorContext()` only returns the active document
- **Cannot activate untitled documents**: No API to programmatically focus an untitled document by ID
- **Can activate saved documents**: Use `documentOpen(path)` or `navigateToFile(path)`
- **Can read any document by ID**: `getSourceEditorContext(id = doc_id)` works for any open document
- **Can edit any document by ID**: `insertText(..., id = doc_id)` and similar work
- **Cannot save untitled to specific path**: `documentSave(id)` has no path parameter, would prompt user interactively. Workaround: write contents to file with `writeLines()`, then `documentOpen()` the saved file

#### Other Tool Principles
- `replace_text_range`: Exact string match, shows ±3 lines context, must be unique in document
- `eval_r`: Has `allow_reassign` param - only true if expecting to overwrite existing vars
- `create_document`: Returns document ID for potential future operations (via eval_r). If path is provided, creates a saved document; otherwise creates untitled
- `source_active_document`: Accepts optional `start_line` and `end_line` parameters to source only specific lines. After sourcing, automatically selects those lines in the editor for visual feedback

### Process Killing (Fallback for Orphaned Servers)
- OS-level: Windows uses `cmd /c "netstat -ano | findstr :PORT"`, macOS/Linux uses `lsof -ti:PORT`
- **Safety**: Check if PID == current R process PID before killing (killing own process = crash)
- Must wrap Windows commands in `cmd /c` for pipes to work in `system()`

### Testing
- Python integration tests use `pytest` with `mcp` client library
- 16 tests total covering all tools including document operations
- Document tests verify the active document workflow
- Tests include both untitled and saved document creation
- Use temporary files for testing `open_document_file` and `create_document` with path

### Code Style
- Line length limit: 80 characters (tidyverse style guide)
- Long strings use `glue::glue()` with `\\` backslash continuation for multiline
- styler can auto-format code but cannot automatically break long lines by character count

## Common Pitfalls
1. **Empty JSON objects**: Use `names(obj) <- character(0)`, NOT just `list()` (becomes array `[]` not object `{}`)
2. **setNames() in .onLoad()**: Not available during early package load - use explicit name assignment
3. **httpuv::listServers()**: Only shows servers in current session, not across namespace reloads - use persistent ref
4. **Interactive prompts**: `readline()` only works if `interactive() == TRUE`
5. **Document context**: `ctx$contents` is already a character vector (one element per line), don't split by `\n`
6. **Trying to list all docs**: Not possible with rstudioapi - only the active document is accessible without a known ID

## Files to Know
- `R/zzz.R`: `.onLoad()`, `.onDetach()`, `.onUnload()` hooks
- `R/mcp_server.R`: Main server, tool definitions, persistent ref system
- `R/settings.R`: Preferences (port, auto-start), `.Rprofile` manipulation
- `R/mcp_config.R`: `.mcp.json` file management for Claude Code config
- `inst/rstudio/addins.dcf`: RStudio addins menu items
- `tests/test_integration.py`: Python integration tests using MCP client

## Debug Mode
All debug messages use `[DEBUG]` prefix - search/replace to remove for release.

## Server Instructions
Set in `handle_initialize()` result under `instructions` field. Appears in Claude Code's system prompt. Should clearly explain the active document workflow.

## Document Workflow Examples

### Untitled Document
```r
1. create_document("x <- 1")             # Returns ID, becomes active
2. insert_text("\ny <- 2")               # Adds to active doc
3. get_active_document()                  # Reads active doc (shows ID, path, contents)
4. source_active_document()               # Runs all lines
```

### Saved Document
```r
1. create_document("x <- 1", "/path/to/script.R")  # Creates saved file, becomes active
2. replace_text_range("old", "new")                 # Edits active doc
3. source_active_document()                         # Runs active doc
```

### Open Existing File
```r
1. open_document_file("/path/to/script.R")  # Opens and activates
2. replace_text_range("old", "new")          # Edits active doc
3. source_active_document()                   # Runs active doc
```

### Partial Sourcing
```r
1. create_document("line1\nline2\nline3\nline4")  # Create multi-line doc
2. source_active_document(start_line=2, end_line=3)  # Runs only lines 2-3
   # Lines 2-3 are automatically selected in editor for visual feedback
```
