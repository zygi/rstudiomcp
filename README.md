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

<details>
<summary>
You'll probably want Claude Code installed to use with RStudio. Claude Code installation instructions:
</summary>
If you know how to use the command line, just follow the [official instructions](https://docs.claude.com/en/docs/claude-code/setup).
Otherwise, ask Claude (or your preferred AI assistant) this:
```
Please help me install Claude Code. The latest instructions are at https://docs.claude.com/en/docs/claude-code/setup - you should fetch them. Please ask me about what system I use - Windows, WSL, MacOS, Linux, and based on that walk me through. Thanks!
```
</details>


#### RStudio MCP Extension
To install the RStudio MCP extension, run the following lines in your RStudio Console:
```r
# Install from GitHub
install.packages("remotes")
library("remotes")
remotes::install_github("zygi/rstudiomcp")
```

<details><summary>Video guide</summary>


https://github.com/user-attachments/assets/4c955f88-b1f4-449c-856b-e69b47c023f6


</details>

## Per-project Setup

### Option 1: Auto-load

Use the RStudio Addin: **"Enable Auto-load (per project)"**

This adds `library(rstudiomcp)` to your project's `.Rprofile` configuration, so the server starts automatically when you open the project.

Restart your RStudio session after enabling auto-load. You should see the following output:
```
Starting MCP Server on http://localhost:16751
MCP Server started successfully!
Endpoint: http://localhost:16751
Transport: Streamable HTTP (JSON responses, no SSE)
Run stop_mcp_server() to stop the server
Added RStudio MCP server to C:/Users/zygi/Documents/test_proj/.mcp.json
```


### Option 2: Manual start (For development/testing)

```r
library(rstudiomcp)
start_mcp_server()
```

## Usage with Claude Code

1. Start the MCP server in RStudio
2. Open Claude Code inside the project folder (from either the integrated RStudio terminal, or external terminal)
3. Claude Code should automatically detect the server and connect to it! You can verify that by typing `/mcp` and looking at the details.

You can now ask Claude Code to interact with your R session!

## Simple Troubleshooting

If you're having problems setting this up, paste the following into Claude:
```
Hi! I'm trying to set up RStudio-MCP to use with a Claude Code session but it's not working.
Could you please help me debug? The project readme is at https://github.com/zygi/rstudiomcp/blob/master/README.md
(but maybe fetch it as a raw file.)
```

## Available Tools

Claude Code can use these tools:

### Code Execution
- `eval_r` - Execute R code in the R session
- `source_active_document` - Run the currently active R script (like clicking Source button). Optional: specify `start_line` and `end_line` to source only specific lines

### Environment Inspection
- `list_environments` - List available R environments
- `list_objects` - List objects in an environment
- `get_object` - Get detailed object information (type, class, structure, preview)
- `get_console_history` - View recent console commands

### Document Editing
> **Note**: All document editing tools work on the currently active document only.
> Use `create_document` to create new docs or `open_document_file` to open saved files.

- `create_document` - Create a new document with optional file path (becomes active automatically)
- `open_document_file` - Open or refocus a saved document file by path
- `get_active_document` - Read the active document (shows ID, path, and contents)
- `insert_text` - Insert text at cursor or specific location in the active document
- `replace_text_range` - Replace text with exact string matching in the active document

### Visualization
- `get_current_plot` - Capture the current plot as an image
- `get_latest_viewer_content` - Get HTML content of the last rendered page in the Viewer pane

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

Default port is **16751**.

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


## Technical Troubleshooting

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
```bash
npx @modelcontextprotocol/inspector http://localhost:16751/
```

## Technical Details

- The R package runs in RStudio's R session and starts up an HTTP MCP server on 127.0.0.1
- It also writes (or updates) a `.mcp.json` file in the project directory.
- Once you start Claude Code, it sees this file and attempts to connect to the MCP server.

### Notes:
- To allow MCP to access what's on the Viewer panel, the server needs to wrap the `viewer` function. This is obviously hacky, I haven't seen it break anything yet but please report if you find it a real problem.




## Contributing

Issues and pull requests welcome! The author isn't an R expert so some stupid decisions may have been made.
This is not an official RStudio product.
