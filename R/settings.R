# MCP Server Settings

# Internal helper to get preferences with caching
get_pref <- function(name, default, coerce = identity) {
  opt_name <- paste0("rstudiomcp.", name)
  value <- getOption(opt_name)
  if (is.null(value)) {
    value <- tryCatch(
      rstudioapi::readPreference(opt_name, default = default),
      error = function(e) default
    )
    opts <- list(coerce(value))
    names(opts) <- opt_name
    options(opts)
  }
  coerce(value)
}

# Internal helper to set preferences
set_pref <- function(name, value) {
  opt_name <- paste0("rstudiomcp.", name)
  opts <- list(value)
  names(opts) <- opt_name
  options(opts)
  tryCatch(
    rstudioapi::writePreference(opt_name, value),
    error = function(e) message("Warning: Failed to write preference: ", e$message)
  )
  invisible(value)
}

#' @export
get_mcp_port <- function() {
  get_pref("port", 16731, as.integer)
}

#' @export
set_mcp_port <- function(port) {
  set_pref("port", as.integer(port))
}

#' @export
get_mcp_auto_start <- function() {
  get_pref("auto_start", TRUE, isTRUE)
}

#' @export
set_mcp_auto_start <- function(auto_start) {
  set_pref("auto_start", isTRUE(auto_start))
}

#' Configure MCP Server Settings
#'
#' Opens a Shiny gadget to configure MCP server settings
#'
#' @export
configure_mcp_server <- function() {
  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar("MCP Server Settings"),
    miniUI::miniContentPanel(
      shiny::tags$div(
        style = "padding: 20px;",
        shiny::numericInput("port", "Port Number:",
          value = get_mcp_port(),
          min = 1024, max = 65535, step = 1
        ),
        shiny::checkboxInput("auto_start", "Auto-start server when package loads",
          value = get_mcp_auto_start()
        ),
        shiny::hr(),
        shiny::tags$p(
          shiny::tags$strong("Note:"),
          "Auto-start changes take effect on next R session restart."
        ),
        shiny::hr(),
        shiny::actionButton("restart", "Save & Restart Server",
          class = "btn-primary", style = "width: 100%;"
        )
      )
    )
  )

  server <- function(input, output, session) {
    save_settings <- function() {
      set_mcp_port(input$port)
      set_mcp_auto_start(input$auto_start)
    }

    shiny::observeEvent(input$done, {
      save_settings()
      shiny::stopApp()
    })

    shiny::observeEvent(input$restart, {
      save_settings()
      if (!is.null(.rstudiomcp_env$server)) stop_mcp_server()
      start_mcp_server(port = input$port) # This will call add_to_mcp_config() internally
      shiny::showNotification(paste0("Server restarted on port ", input$port),
        type = "message", duration = 3
      )
      Sys.sleep(1)
      shiny::stopApp()
    })

    shiny::observeEvent(input$cancel, shiny::stopApp())
  }

  viewer <- shiny::dialogViewer("MCP Server Settings", width = 400, height = 350)
  shiny::runGadget(ui, server, viewer = viewer)
}

# Get the exact auto-load code block
#' @keywords internal
.get_autoload_code <- function() {
  "
# Auto-load rstudiomcp package
tryCatch(
  library(rstudiomcp),
  error = function(e) warning(\"Failed to load rstudiomcp: \", e$message)
)
"
}

#' Setup Auto-load on RStudio Startup
#'
#' Adds library(rstudiomcp) to project .Rprofile and enables auto-start
#'
#' @export
setup_autoload <- function() {
  # Check if running in RStudio
  if (!rstudioapi::isAvailable()) {
    stop("rstudiomcp requires RStudio. Please run this package in RStudio IDE.")
  }

  rprofile_path <- file.path(getwd(), ".Rprofile")

  # Check if already setup
  if (file.exists(rprofile_path)) {
    content <- paste(readLines(rprofile_path, warn = FALSE), collapse = "\n")
    if (grepl("# Auto-load rstudiomcp package", content, fixed = TRUE)) {
      message("Auto-load already configured in ", rprofile_path)
      set_mcp_auto_start(TRUE)
      return(invisible(FALSE))
    }
  }

  # Warn user
  message("This will add auto-load code for rstudiomcp to your project .Rprofile")
  message("Location: ", rprofile_path)
  message("\nNote: This is project-specific. Other projects will need separate setup.")

  if (interactive()) {
    response <- readline("Continue? (yes/no): ")
    if (tolower(trimws(response)) != "yes") {
      message("Setup cancelled")
      return(invisible(FALSE))
    }
  }

  # Add to .Rprofile
  cat(.get_autoload_code(), file = rprofile_path, append = TRUE)

  # Enable auto-start
  set_mcp_auto_start(TRUE)

  message("\n\u2713 Added auto-load code to ", rprofile_path)
  message("\u2713 Enabled MCP server auto-start")
  message("\nRestart R session for changes to take effect")
  invisible(TRUE)
}

#' Disable Auto-load on RStudio Startup
#'
#' Removes library(rstudiomcp) from project .Rprofile and disables auto-start
#'
#' @export
disable_autoload <- function() {
  rprofile_path <- file.path(getwd(), ".Rprofile")

  if (!file.exists(rprofile_path)) {
    message("No .Rprofile found at ", rprofile_path)
    set_mcp_auto_start(FALSE)
    return(invisible(FALSE))
  }

  content <- paste(readLines(rprofile_path, warn = FALSE), collapse = "\n")

  # Check if our auto-load code is present
  if (!grepl("# Auto-load rstudiomcp package", content, fixed = TRUE)) {
    message("rstudiomcp auto-load code not found in ", rprofile_path)
    set_mcp_auto_start(FALSE)
    return(invisible(FALSE))
  }

  # Remove the exact auto-load code block
  new_content <- gsub(.get_autoload_code(), "", content, fixed = TRUE)
  writeLines(new_content, rprofile_path)

  # Disable auto-start
  set_mcp_auto_start(FALSE)

  message("\u2713 Removed library(rstudiomcp) from ", rprofile_path)
  message("\u2713 Disabled MCP server auto-start")
  message("\nRestart R session for changes to take effect")
  invisible(TRUE)
}
