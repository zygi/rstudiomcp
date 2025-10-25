# rstudiomcp

MCP (Model Context Protocol) server for RStudio - Bridge your RStudio session with Claude Code.

## What is this?

This R package runs a local MCP server inside your RStudio session, allowing Claude Code to:
- Execute R code in your session
- Inspect objects and environments
- Read and edit open documents
- Source R scripts
- Capture plots from the Plots pane
- Access HTML content from the Viewer pane

## Installation

```r
# Install from GitHub
install.packages("remotes")
library("remotes")
remotes::install_github("zygi/rstudiomcp")
```

## Quick Start

### Option 1: Auto-load

Use the RStudio Addin: **"Enable Auto-load (per project)"**

This adds `library(rstudiomcp)` to your project's `.Rprofile`, so the server starts automatically when you open the project.

### Option 2: Manual start (For development/testing)

```r
library(rstudiomcp)
start_mcp_server()
```

## Usage with Claude Code

1. Start the MCP server in RStudio (automatically creates `.mcp.json`)
2. Open the project folder in Claude Code
3. Claude Code auto-detects the MCP server via `.mcp.json`

You can now ask Claude Code to interact with your R session!

## Troubleshooting

If you're having problems setting this up, paste the following into Claude:
```
Hi! I'm trying to set up RStudio-MCP to use with a Claude Code session but it's not working.
Could you please help me debug? The project readme is at https://github.com/zygi/rstudiomcp/README.md
(but maybe fetch it as a raw file.)
```

## Available Tools

Claude Code can use these tools:

### Code Execution
- `eval_r` - Execute R code in the R session
- `source_active_document` - Run the currently active R script (like clicking Source button)

### Environment Inspection
- `list_environments` - List available R environments
- `list_objects` - List objects in an environment
- `get_object` - Get detailed object information (type, class, structure, preview)
- `get_console_history` - View recent console commands

### Document Editing
> **Note**: All document editing tools work on the currently active document only.
> Use `create_untitled_document` to create new docs or `open_document_file` to open saved files.

- `create_untitled_document` - Create a new untitled document (becomes active automatically)
- `open_document_file` - Open or refocus a saved document file by path
- `get_active_document` - Read the active document (shows ID, path, and contents)
- `insert_text` - Insert text at cursor or specific location in the active document
- `replace_text_range` - Replace text with exact string matching in the active document

### Visualization
- `get_current_plot` - Capture the current plot as an image
- `get_viewer_content` - Get HTML content from the Viewer pane

## Configuration

### Check Status
```r
mcp_status()
```

Or use the RStudio Addin: **"MCP Server Status"**

### Change Port
```r
configure_mcp_server()
```

Default port is **16731**.

### Restart Server
```r
restart_mcp_server()
```

Or use the RStudio Addin: **"Restart MCP Server"**

### Disable Auto-start
```r
disable_autoload()
```

Or use the RStudio Addin: **"Disable Auto-load (per project)"**


## Troubleshooting

### "Address already in use"
The port is occupied. Restart the server:
```r
restart_mcp_server()
```

If that prompts to kill a process, type `yes` to confirm.

Or change the port:
```r
configure_mcp_server()
```

### Server won't start after sleep/wake
The server may get orphaned. Use:
```r
restart_mcp_server()
```

## Development

See `CLAUDE.md` for developer notes and architecture details.
Once the server is up, you can also use MCP Inspector for debugging:
```
TODO insert command
```

## Technical Details

- The R package runs in RStudio's R session and starts up an HTTP MCP server on 127.0.0.1
- It also writes (or updates) a `.mcp.json` file in the project directory.
- Once you start Claude Code, it sees this file and attempts to connect to the MCP server.

### Notes:
- To allow the MCP access what's on the panel, the server needs to wrap the `viewer` function. This is obviously hacky, I haven't seen it break anything yet but please report if you find it a real problem.




## Contributing

Issues and pull requests welcome! The author isn't an R expert so some stupid decisions may have been made.
This is not an official RStudio product.
