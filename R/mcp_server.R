# Package environment
.rstudiomcp_env <- new.env(parent = emptyenv())
.rstudiomcp_env$server <- NULL
.rstudiomcp_env$port <- NULL
.rstudiomcp_env$sse_connections <- list()
.rstudiomcp_env$last_url <- NULL
.rstudiomcp_env$original_viewer <- NULL

# Persistent server reference (survives namespace reloads)
get_server_ref <- function() {
  if (exists(".rstudiomcp_server", envir = .GlobalEnv)) {
    get(".rstudiomcp_server", envir = .GlobalEnv)
  }
}

set_server_ref <- function(server, port) {
  assign(".rstudiomcp_server", list(server = server, port = port), envir = .GlobalEnv)
}

clear_server_ref <- function() {
  if (exists(".rstudiomcp_server", envir = .GlobalEnv)) {
    rm(".rstudiomcp_server", envir = .GlobalEnv)
  }
}

# Kill process using a port at OS level (fallback for orphaned servers)
kill_process_on_port <- function(port, ask_confirmation = TRUE) {
  os_type <- Sys.info()["sysname"]
  pid <- NULL

  if (os_type == "Windows") {
    cmd <- paste0('cmd /c "netstat -ano | findstr :', port, '"')
    result <- suppressWarnings(system(cmd, intern = TRUE))
    if (length(result) > 0 && !inherits(result, "error")) {
      for (line in result) {
        if (grepl("LISTENING", line)) {
          parts <- strsplit(trimws(line), "\\s+")[[1]]
          pid <- parts[length(parts)]
          break
        }
      }
    }
  } else {
    cmd <- paste0("lsof -ti:", port)
    result <- tryCatch(
      {
        suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE))
      },
      error = function(e) character(0)
    )
    if (length(result) > 0 && nzchar(result[1])) pid <- result[1]
  }

  if (is.null(pid) || !nzchar(pid)) {
    return(TRUE)
  }

  # Check if the PID is the current R process
  if (pid == as.character(Sys.getpid())) {
    message("ERROR: Port ", port, " is being used by an orphaned httpuv server in the current R session.")
    message("Cannot kill current R process. Please restart R session or change port with configure_mcp_server()")
    return(FALSE)
  }

  # Ask for confirmation before killing a different process
  should_kill <- TRUE
  if (ask_confirmation && interactive()) {
    message("Warning: Found external process (PID ", pid, ") using port ", port)
    response <- readline("Kill this process? (yes/no): ")
    should_kill <- (tolower(trimws(response)) == "yes")
  }

  if (should_kill) {
    kill_cmd <- if (os_type == "Windows") paste0("taskkill /PID ", pid, " /F") else paste0("kill -9 ", pid)
    result <- tryCatch(
      {
        system(kill_cmd, ignore.stdout = TRUE, ignore.stderr = TRUE)
        message("Killed process ", pid, " on port ", port)
        Sys.sleep(0.5)
        TRUE
      },
      error = function(e) {
        message("Failed to kill process: ", e$message)
        FALSE
      }
    )
    return(result)
  } else {
    message("Process not killed. Port ", port, " may still be in use.")
    return(FALSE)
  }
}

# Check and stop orphaned servers on a given port
stop_orphaned_server <- function(port, ask_confirmation = TRUE) {
  all_servers <- httpuv::listServers()
  orphaned_server <- NULL

  for (srv in all_servers) {
    srv_port <- tryCatch(srv$getPort(), error = function(e) NULL)
    if (!is.null(srv_port) && srv_port == port) {
      orphaned_server <- srv
      break
    }
  }

  if (!is.null(orphaned_server)) {
    should_stop <- TRUE
    if (ask_confirmation && interactive()) {
      message("Warning: Found orphaned httpuv server on port ", port)
      response <- readline("Forcefully stop this server? (yes/no): ")
      should_stop <- (tolower(trimws(response)) == "yes")
    }

    if (should_stop) {
      tryCatch(
        {
          httpuv::stopServer(orphaned_server)
          clear_server_ref()
          message("Stopped orphaned server on port ", port)
          Sys.sleep(0.5)
          return(TRUE)
        },
        error = function(e) {
          stop("Failed to stop orphaned server: ", e$message)
        }
      )
    } else {
      message("Orphaned server not stopped. Port ", port, " may still be in use.")
      return(FALSE)
    }
  }

  # Fallback: check at OS level
  return(kill_process_on_port(port, ask_confirmation))
}

# MCP response helpers
text_response <- function(text) {
  list(content = list(list(type = "text", text = text)))
}

get_env <- function(args) {
  if (!is.null(args$envir) && nzchar(args$envir)) {
    tryCatch(as.environment(args$envir), error = function(e) .GlobalEnv)
  } else {
    .GlobalEnv
  }
}

mk_prop <- function(type, desc) list(type = type, description = desc)

mk_tool <- function(name, desc, props = list(), required = character(0)) {
  # Create empty object for properties if none provided
  if (length(props) == 0) {
    props <- list()
    names(props) <- character(0)
  }

  list(
    name = name,
    description = desc,
    inputSchema = list(
      type = "object",
      properties = props,
      required = if (length(required) > 0) as.list(required) else list()
    )
  )
}

#' Start MCP Server
#'
#' Launches the MCP server for Claude Code integration via SSE transport
#'
#' @param port Port number for the server (default: from settings or 3000)
#' @param .test_mode Internal parameter for testing, bypasses RStudio check
#' @keywords internal
#' @export
start_mcp_server <- function(port = NULL, .test_mode = FALSE) {
  # Check if running in RStudio
  if (!.test_mode && !rstudioapi::isAvailable()) {
    stop("rstudiomcp requires RStudio. Please run this package in RStudio IDE.")
  }

  if (is.null(port)) {
    port <- get_mcp_port()
  }

  # Check for orphaned server from previous namespace (survives devtools::load_all)
  old_ref <- get_server_ref()
  if (!is.null(old_ref)) {
    message("Found existing server, stopping it first...")
    tryCatch(
      {
        httpuv::stopServer(old_ref$server)
      },
      error = function(e) {
        message("Note: Could not stop old server: ", e$message)
      }
    )
    clear_server_ref()
  }

  # Also check if .rstudiomcp_env has a server (normal case)
  if (!is.null(.rstudiomcp_env$server)) {
    message("MCP Server already running on port ", .rstudiomcp_env$port)
    message("Stop it first with stop_mcp_server()")
    return(invisible(NULL))
  }

  # Check for and stop any orphaned servers on this port
  if (!stop_orphaned_server(port, ask_confirmation = TRUE)) {
    stop("Cannot start server: port ", port, " is in use. Change port with configure_mcp_server()")
  }

  message("Starting MCP Server on http://localhost:", port)

  # MCP request handlers
  handle_initialize <- function(id, params) {
    list(
      jsonrpc = "2.0",
      id = id,
      result = list(
        protocolVersion = "2024-11-05",
        serverInfo = list(
          name = "rstudio",
          version = "0.1.0",
          title = "RStudio MCP Server"
        ),
        capabilities = list(
          tools = list(listChanged = FALSE) # Static tool list
        ),
        instructions = "This server provides access to an active RStudio session. You can execute R code, inspect the environment and objects, edit documents, source scripts, and capture plots. All document editing tools (insert_text, replace_text_range, get_active_document, source_active_document) work on the CURRENTLY ACTIVE document only. To work with a specific document: (1) use create_untitled_document to create a new one (becomes active automatically), OR (2) use open_document_file to open/focus a saved file. After that, all document operations apply to that now-active document. Your API doesn't allow you to list or navigate between open documents. Don't destroy the user's work - only perform mutable non-undoable actions like eval_r or source_active_document if the user expects that. IMPORTANT: WHEN DOING SOMETHING DESTRUCTIVE, LIKE DELETING FILES OR FORCIBLY CLOSING DOCUMENTS, ALWAYS ASK THE USER FIRST."
      )
    )
  }

  handle_tools_list <- function(id, params) {
    list(
      jsonrpc = "2.0",
      id = id,
      result = list(
        tools = list(
          mk_tool(
            "eval_r", "Execute R code in the RStudio session. Note that this is intended for short commands - if you're generating long scripts, instead create a new document, and then source it, so the user can easily inspect it.",
            list(
              code = mk_prop("string", "R code to execute"),
              envir = mk_prop("string", "Environment name to execute in (default: .GlobalEnv)"),
              allow_reassign = mk_prop("boolean", "Allow overwriting existing variables (default: false). Only set to true if you expect an object with this name to already exist. If false, will error if code would overwrite existing objects.")
            ),
            "code"
          ),
          mk_tool("list_environments", "List all available environments in the R session"),
          mk_tool(
            "list_objects", "List object names in the R environment",
            list(envir = mk_prop("string", "Environment name (default: .GlobalEnv)"))
          ),
          mk_tool(
            "get_object", "Get details about a specific R object (type, class, structure, and preview of contents)",
            list(
              name = mk_prop("string", "Name of the object to inspect"),
              envir = mk_prop("string", "Environment name to search in (default: .GlobalEnv)")
            ),
            "name"
          ),
          mk_tool(
            "get_console_history", "Get the R console command history",
            list(max_lines = mk_prop("number", "Maximum number of recent commands to return (default: 50)"))
          ),
          mk_tool(
            "get_active_document", "Read the contents of the currently active document in RStudio",
            list(
              offset = mk_prop("number", "Line number to start reading from (optional)"),
              limit = mk_prop("number", "Number of lines to read (optional)")
            )
          ),
          mk_tool(
            "create_untitled_document", "Create a new untitled document with the given text. The new document becomes active automatically.",
            list(text = mk_prop("string", "Text content for the new document")),
            "text"
          ),
          mk_tool(
            "open_document_file", "Open a saved document file by path, or refocus it if already open. The document becomes active.",
            list(file_path = mk_prop("string", "Absolute path to the document file to open")),
            "file_path"
          ),
          mk_tool(
            "insert_text", "Insert text at cursor position or specific location in the currently active document",
            list(
              text = mk_prop("string", "Text to insert"),
              row = mk_prop("number", "Row number to insert at (optional, uses cursor position if not provided)"),
              column = mk_prop("number", "Column number to insert at (optional, uses cursor position if not provided)")
            ),
            "text"
          ),
          mk_tool(
            "replace_text_range", "Replace text in the currently active document (exact string match)",
            list(
              old_string = mk_prop("string", "The text to replace"),
              new_string = mk_prop("string", "The text to replace it with")
            ),
            c("old_string", "new_string")
          ),
          mk_tool("source_active_document", "Source (run) the currently active R document, like clicking the Source button in RStudio"),
          mk_tool(
            "get_current_plot", "Capture the plot currently displayed to the user from the Plots pane as an image file.",
            list(
              width = mk_prop("number", "Image width in pixels (default: 800)"),
              height = mk_prop("number", "Image height in pixels (default: 600)"),
              format = mk_prop("string", "Image format: png, jpeg, bmp, tiff, svg, eps (default: png)"),
              screenshot_filepath = mk_prop("boolean", "If false, return a base64 image to the MCP client. If true, save to temp file and return path instead. (default: false)")
            )
          ),
          mk_tool(
            "get_latest_viewer_content", "Get the HTML content of the last rendered page in RStudio Viewer pane (HTML widgets, interactive plots, etc.)",
            list(
              max_length = mk_prop("number", "Maximum number of characters to return (default: 10000)"),
              offset = mk_prop("number", "Character offset to start reading from (default: 0, for pagination)")
            )
          )
        )
      )
    )
  }

  handle_tools_call <- function(id, params) {
    tool_name <- params$name
    args <- if (is.null(params$arguments)) list() else params$arguments

    result <- tryCatch(
      {
        if (tool_name == "eval_r") {
          envir <- get_env(args)
          allow_reassign <- isTRUE(args$allow_reassign)

          if (!allow_reassign) {
            assignments <- tryCatch(detect_assignments(args$code),
              error = function(e) character(0)
            )
            if (length(assignments) > 0) {
              existing <- assignments[sapply(assignments, exists, envir = envir)]
              if (length(existing) > 0) {
                stop(
                  "Code would overwrite existing variable(s): ", paste(existing, collapse = ", "), "\n",
                  "Set allow_reassign=true to allow modifications, or use different variable names."
                )
              }
            }
          }

          output <- capture.output(result <- withVisible(eval(parse(text = args$code), envir = envir)))
          # If result is visible and not NULL, print it
          result_output <- if (result$visible && !is.null(result$value)) {
            capture.output(print(result$value))
          } else {
            character(0)
          }
          combined <- paste(c(output, result_output), collapse = "\n")
          tryCatch(rstudioapi::executeCommand("refreshEnvironment"), error = function(e) NULL)
          text_response(combined)
        } else if (tool_name == "list_environments") {
          text_response(paste(search(), collapse = "\n"))
        } else if (tool_name == "list_objects") {
          objects <- ls(envir = get_env(args))
          text_response(if (length(objects) > 0) paste(objects, collapse = "\n") else "(empty environment)")
        } else if (tool_name == "get_object") {
          if (is.null(args$name)) stop("Object name is required")
          obj <- get(args$name, envir = get_env(args))
          info <- capture.output(print(str(obj)), print(summary(obj)))
          text_response(paste(info, collapse = "\n"))
        } else if (tool_name == "get_console_history") {
          max_lines <- if (!is.null(args$max_lines)) as.integer(args$max_lines) else 50
          history_lines <- tryCatch(
            {
              temp_file <- tempfile(pattern = "rhistory_", fileext = ".txt")
              savehistory(temp_file)
              all_history <- readLines(temp_file, warn = FALSE)
              unlink(temp_file)
              if (length(all_history) > max_lines) tail(all_history, max_lines) else all_history
            },
            error = function(e) paste("Error retrieving history:", e$message)
          )
          text_response(paste(history_lines, collapse = "\n"))
        } else if (tool_name == "get_active_document") {
          ctx <- rstudioapi::getSourceEditorContext()

          # Format header with ID and path
          doc_path <- if (nzchar(ctx$path)) ctx$path else "<untitled>"
          header <- paste0("ID: ", ctx$id, "\nPath: ", doc_path, "\n\n")

          # Format contents with line numbers
          all_lines <- ctx$contents # Already a character vector, one element per line
          offset <- if (!is.null(args$offset)) as.integer(args$offset) else 1
          limit <- if (!is.null(args$limit)) as.integer(args$limit) else length(all_lines)
          end_line <- min(offset + limit - 1, length(all_lines))
          selected_lines <- all_lines[offset:end_line]
          formatted_content <- paste(sprintf("%6d\t%s", offset:end_line, selected_lines), collapse = "\n")

          text_response(paste0(header, formatted_content))
        } else if (tool_name == "create_untitled_document") {
          doc_id <- rstudioapi::documentNew(text = args$text, type = "r", execute = FALSE)
          text_response(paste0("Created new document with ID: ", doc_id))
        } else if (tool_name == "open_document_file") {
          # Use documentOpen which opens and focuses the file
          doc_id <- rstudioapi::documentOpen(args$file_path)
          text_response(paste0("Opened document: ", args$file_path, " (ID: ", doc_id, ")"))
        } else if (tool_name == "insert_text") {
          ctx <- rstudioapi::getSourceEditorContext()
          location <- if (!is.null(args$row) && !is.null(args$column)) {
            rstudioapi::document_position(as.integer(args$row), as.integer(args$column))
          } else {
            ctx$selection[[1]]$range$start
          }
          rstudioapi::insertText(location = location, text = args$text, id = ctx$id)
          row_num <- if (is.null(args$row)) location["row"] else args$row
          col_num <- if (is.null(args$column)) location["column"] else args$column
          text_response(paste0("Text inserted at row ", row_num, ", column ", col_num))
        } else if (tool_name == "replace_text_range") {
          ctx <- rstudioapi::getSourceEditorContext()
          contents <- paste(ctx$contents, collapse = "\n")
          if (!grepl(args$old_string, contents, fixed = TRUE)) {
            stop("old_string not found in document")
          }
          occurrences <- gregexpr(args$old_string, contents, fixed = TRUE)[[1]]
          if (length(occurrences) > 1 && occurrences[1] != -1) {
            stop("old_string appears multiple times in document. Please make it more specific.")
          }
          new_contents <- sub(args$old_string, args$new_string, contents, fixed = TRUE)
          rstudioapi::setDocumentContents(new_contents, id = ctx$id)

          # Show context around the change (like Edit tool)
          new_lines <- strsplit(new_contents, "\n")[[1]]
          # Find line containing the replacement
          changed_line <- which(grepl(args$new_string, new_lines, fixed = TRUE))[1]
          if (!is.na(changed_line)) {
            start_line <- max(1, changed_line - 3)
            end_line <- min(length(new_lines), changed_line + 3)
            context_lines <- new_lines[start_line:end_line]
            formatted <- paste(sprintf("%6d\t%s", start_line:end_line, context_lines), collapse = "\n")
            text_response(paste0("Text replaced successfully. Result:\n\n", formatted))
          } else {
            text_response("Text replaced successfully")
          }
        } else if (tool_name == "source_active_document") {
          ctx <- rstudioapi::getSourceEditorContext()

          # Source the document
          temp_file <- tempfile(fileext = ".R")
          writeLines(ctx$contents, temp_file)

          output <- capture.output({
            source(temp_file, echo = TRUE)
          })
          unlink(temp_file)

          doc_name <- if (nzchar(ctx$path)) basename(ctx$path) else "Untitled"
          text_response(paste0("Sourced document: ", doc_name, "\n\n", paste(output, collapse = "\n")))
        } else if (tool_name == "get_current_plot") {
          width <- if (!is.null(args$width)) as.integer(args$width) else 800
          height <- if (!is.null(args$height)) as.integer(args$height) else 600
          format <- if (!is.null(args$format)) args$format else "png"
          screenshot_filepath <- isTRUE(args$screenshot_filepath)

          valid_formats <- c("png", "jpeg", "bmp", "tiff", "emf", "svg", "eps")
          if (!(format %in% valid_formats)) stop("Invalid format. Must be one of: ", paste(valid_formats, collapse = ", "))

          temp_file <- tempfile(pattern = "rstudio_plot_", fileext = paste0(".", format))
          rstudioapi::savePlotAsImage(file = temp_file, format = format, width = width, height = height)
          if (!file.exists(temp_file)) stop("Failed to save plot. Make sure a plot is displayed in the Plots pane.")

          if (screenshot_filepath) {
            text_response(paste0("Plot saved to: ", temp_file, "\nFormat: ", format, ", Size: ", width, "x", height))
          } else {
            image_data <- base64enc::base64encode(temp_file)
            unlink(temp_file)
            mime_type <- switch(format,
              "png" = "image/png",
              "jpeg" = "image/jpeg",
              "bmp" = "image/bmp",
              "tiff" = "image/tiff",
              "svg" = "image/svg+xml",
              "eps" = "application/postscript",
              "emf" = "image/emf",
              "image/png"
            )
            list(content = list(list(type = "image", data = image_data, mimeType = mime_type)))
          }
        } else if (tool_name == "get_latest_viewer_content") {
          max_length <- if (!is.null(args$max_length)) as.integer(args$max_length) else 10000
          offset <- if (!is.null(args$offset)) as.integer(args$offset) else 0

          if (is.null(.rstudiomcp_env$last_url)) {
            stop("No viewer content found. Make sure something is displayed in the RStudio Viewer pane.")
          }
          viewer_url <- .rstudiomcp_env$last_url
          if (!file.exists(viewer_url) && !grepl("^https?://", viewer_url)) {
            stop("Viewer content not found at: ", viewer_url)
          }

          html_content <- tryCatch(paste(readLines(viewer_url, warn = FALSE), collapse = "\n"),
            error = function(e) stop("Failed to read viewer content: ", e$message)
          )
          total_length <- nchar(html_content)
          start_pos <- offset + 1
          end_pos <- min(offset + max_length, total_length)
          paginated_content <- if (start_pos > total_length) "" else substr(html_content, start_pos, end_pos)
          text_response(paste0(
            "HTML content (", start_pos - 1, "-", end_pos, " of ", total_length, " chars):\n\n",
            paginated_content
          ))
        } else {
          stop("Unknown tool: ", tool_name)
        }
      },
      error = function(e) {
        return(list(
          error = list(
            code = -32603,
            message = paste("Tool execution error:", e$message)
          )
        ))
      }
    )

    response <- list(
      jsonrpc = "2.0",
      id = id
    )

    if (!is.null(result$error)) {
      response$error <- result$error
    } else {
      response$result <- result
    }

    response
  }

  # HTTP handler
  app <- list(
    call = function(req) {
      # Handle CORS
      headers <- list(
        "Access-Control-Allow-Origin" = "*",
        "Access-Control-Allow-Methods" = "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers" = "Content-Type"
      )

      if (req$REQUEST_METHOD == "OPTIONS") {
        return(list(
          status = 200L,
          headers = headers,
          body = ""
        ))
      }

      # GET requests (for SSE streaming) - return 405 since we don't support SSE
      if (req$REQUEST_METHOD == "GET") {
        return(list(
          status = 405L,
          headers = list("Content-Type" = "text/plain"),
          body = "SSE streaming not supported"
        ))
      }

      # POST requests to root endpoint (Streamable HTTP transport)
      if (req$PATH_INFO == "/" && req$REQUEST_METHOD == "POST") {
        body <- rawToChar(req$rook.input$read())

        # Parse JSON with error handling
        msg <- tryCatch(
          jsonlite::fromJSON(body, simplifyVector = FALSE),
          error = function(e) {
            # Return JSON-RPC parse error
            headers$"Content-Type" <- "application/json"
            return(list(
              status = 200L,
              headers = headers,
              body = jsonlite::toJSON(list(
                jsonrpc = "2.0",
                id = NULL,
                error = list(code = -32700, message = "Parse error")
              ), auto_unbox = TRUE)
            ))
          }
        )

        # If parse failed, msg is already a response list
        if (!is.null(msg$status)) {
          return(msg)
        }

        response <- if (msg$method == "initialize") {
          handle_initialize(msg$id, msg$params)
        } else if (msg$method == "tools/list") {
          handle_tools_list(msg$id, msg$params)
        } else if (msg$method == "tools/call") {
          handle_tools_call(msg$id, msg$params)
        } else {
          list(
            jsonrpc = "2.0",
            id = msg$id,
            error = list(
              code = -32601,
              message = paste("Method not found:", msg$method)
            )
          )
        }

        headers$"Content-Type" <- "application/json"
        return(list(
          status = 200L,
          headers = headers,
          body = jsonlite::toJSON(response, auto_unbox = TRUE)
        ))
      }

      # Default response
      list(
        status = 404L,
        headers = list("Content-Type" = "text/plain"),
        body = "Not Found"
      )
    }
  )

  .rstudiomcp_env$server <- httpuv::startServer("127.0.0.1", port, app)
  .rstudiomcp_env$port <- port

  # Store persistent reference (survives devtools::load_all)
  set_server_ref(.rstudiomcp_env$server, port)

  message("MCP Server started successfully!")
  message("Endpoint: http://localhost:", port)
  message("Transport: Streamable HTTP (JSON responses, no SSE)")
  message("Run stop_mcp_server() to stop the server")

  # Update .mcp.json (unless in test mode)
  if (!.test_mode) {
    add_to_mcp_config()
  }

  invisible(.rstudiomcp_env$server)
}

#' Stop MCP Server
#'
#' Stops the running MCP server
#'
#' @export
stop_mcp_server <- function() {
  stopped <- FALSE
  port <- get_mcp_port()

  # Stop server from current namespace
  if (!is.null(.rstudiomcp_env$server)) {
    httpuv::stopServer(.rstudiomcp_env$server)
    .rstudiomcp_env$server <- NULL
    .rstudiomcp_env$port <- NULL
    stopped <- TRUE
  }

  # Also check and stop persistent reference (in case namespace was reloaded)
  old_ref <- get_server_ref()
  if (!is.null(old_ref)) {
    tryCatch(
      {
        httpuv::stopServer(old_ref$server)
        stopped <- TRUE
      },
      error = function(e) {
        message("Warning: failed to stop server from persistent ref: ", e$message)
      }
    )
    clear_server_ref()
  }

  # Check for and stop any orphaned servers on this port
  if (stop_orphaned_server(port, ask_confirmation = TRUE)) {
    stopped <- TRUE
  }

  if (stopped) {
    message("MCP Server stopped")
  } else {
    message("No MCP server is running")
  }

  invisible(NULL)
}

#' Restart MCP Server
#'
#' Stops and restarts the MCP server. Useful for recovering from connection issues.
#'
#' @export
restart_mcp_server <- function() {
  message("Restarting MCP Server...")
  stop_mcp_server()
  Sys.sleep(0.5) # Brief pause to ensure port is released
  start_mcp_server()
  invisible(NULL)
}

#' Check MCP Server Status
#'
#' Returns whether the MCP server is currently running
#'
#' @export
mcp_status <- function() {
  if (is.null(.rstudiomcp_env$server)) {
    message("MCP Server is not running")
    return(FALSE)
  } else {
    message("MCP Server is running on port ", .rstudiomcp_env$port)
    message("Endpoint: http://localhost:", .rstudiomcp_env$port)
    message("Transport: Streamable HTTP (JSON responses, no SSE)")
    return(TRUE)
  }
}
