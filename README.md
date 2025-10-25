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

All interactions happen over localhost (127.0.0.1) for security.

## Installation

```r
# Install from GitHub
devtools::install_github("yourusername/rstudiomcp")
```

## Quick Start

### Option 1: Auto-start (Recommended for regular use)

Use the RStudio Addin: **"Enable Auto-load (per project)"** or run:
```r
library(rstudiomcp)
setup_autoload()
```

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

## Available Tools

Claude Code can use these tools:

### Code Execution
- `eval_r` - Execute R code with optional environment control
- `source_document` - Run an R script (like clicking Source button)

### Environment Inspection
- `list_environments` - List available R environments
- `list_objects` - List objects in an environment
- `get_object` - Get detailed object information (type, class, structure, preview)
- `get_console_history` - View recent console commands

### Document Editing
- `list_open_documents` - List all open RStudio documents
- `get_document_contents` - Read document contents
- `insert_text` - Insert text at cursor or specific location
- `replace_text_range` - Replace text with exact string matching

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

## RStudio Addins

After installation, these commands appear in the **Addins** dropdown:
- **Enable Auto-load (per project)** - Add auto-start to project `.Rprofile`
- **Disable Auto-load (per project)** - Remove auto-start from project `.Rprofile`
- **Configure MCP Server** - Change port and settings
- **Restart MCP Server** - Restart the server
- **MCP Server Status** - Check if server is running

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

### Connection lost after devtools::load_all()
This is expected during development. The server automatically stops and restarts. Just reconnect Claude Code with `/mcp`.

## Development

See `CLAUDE.md` for developer notes and architecture details.

### Hot-Reload During Development

```r
devtools::load_all()  # or Ctrl+Shift+L
```

The server will automatically:
1. Stop via `.onDetach()` hook
2. Reload package code
3. Start fresh via `.onLoad()` hook

## How It Works

- Server runs on localhost:16731 (configurable)
- Uses `httpuv` for HTTP server
- Implements MCP Streamable HTTP transport (JSON-RPC 2.0)
- Binds to 127.0.0.1 (localhost only - no external network access)
- Server reference persists in `.GlobalEnv` across `devtools::load_all()`
- Settings stored in RStudio preferences via `rstudioapi`

## Package Structure

```
rstudiomcp/
├── R/
│   ├── mcp_server.R      # Main MCP server and tool handlers
│   ├── mcp_config.R      # .mcp.json file management
│   ├── settings.R        # Preferences and auto-load setup
│   ├── utils.R           # Helper functions
│   └── zzz.R             # Package hooks (.onLoad, .onDetach, .onUnload)
├── inst/
│   └── rstudio/
│       └── addins.dcf    # RStudio Addins configuration
├── tests/
│   └── testthat/         # Unit tests
├── CLAUDE.md             # Developer notes for AI assistants
├── LICENSE               # MIT License
└── README.md
```

## License

MIT License - Copyright (c) 2025 Zygimantas Straznickas

See LICENSE file for details.

## Contributing

Issues and pull requests welcome!
