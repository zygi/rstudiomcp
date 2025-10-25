# Package hooks

.viewer_env <- new.env(parent = emptyenv())
.viewer_env$last_url <- NULL

.onLoad <- function(libname, pkgname) {
  if (!interactive() || Sys.getenv("RSTUDIO") != "1") {
    if (interactive() && Sys.getenv("RSTUDIO") != "1") {
      packageStartupMessage("Note: rstudiomcp requires RStudio IDE. Package loaded but server not started.")
    }
    return()
  }

  # Auto-start server if enabled
  if (get_mcp_auto_start()) {
    tryCatch({
      start_mcp_server()
      add_to_mcp_config()
    }, error = function(e) {
      packageStartupMessage("ERROR: Failed to start MCP server: ", e$message)
      packageStartupMessage("Port ", get_mcp_port(), " may be in use.")
      packageStartupMessage("Change port via configure_mcp_server()")
    })
  }

  # Set up viewer tracking (wraps viewer to capture URLs)
  tryCatch({
    .viewer_env$original_viewer <- getOption("viewer")
    options(viewer = function(url, height = NULL) {
      .viewer_env$last_url <- url
      .viewer_env$original_viewer(url, height)
    })
  }, error = function(e) {
    message("Warning: Failed to set up viewer tracking: ", e$message)
  })

  # Register exit handler (don't remove from .mcp.json to avoid race conditions)
  reg.finalizer(.mcp_env, function(e) {
    tryCatch(stop_mcp_server(), error = function(err) {
      message("Warning: Error during finalizer: ", err$message)
    })
  }, onexit = TRUE)
}

.onDetach <- function(libpath) {
  # Since devtools::load_all() with reset=TRUE doesn't call .onUnload(),
  # we need to stop the server here
  tryCatch({
    # ONLY stop the server if we have the persistent reference
    # (proof that it's our server). Never arbitrarily stop servers via listServers().
    old_ref <- get_server_ref()

    if (!is.null(old_ref)) {
      port <- get_mcp_port()
      ref_port <- tryCatch(old_ref$server$getPort(), error = function(e) NULL)
      if (!is.null(ref_port) && ref_port == port) {
        tryCatch(old_ref$server$stop(), error = function(e) {
          message("Warning during .onDetach: failed to stop server: ", e$message)
        })
      }
    }

    # Restore viewer
    if (!is.null(.viewer_env$original_viewer)) {
      options(viewer = .viewer_env$original_viewer)
    }
  }, error = function(e) {
    message("Warning during .onDetach: ", e$message)
  })
}

.onUnload <- function(libpath) {
  # This is called on true package unload (not devtools::load_all)
  tryCatch({
    stop_mcp_server()
    remove_from_mcp_config()
  }, error = function(e) {
    message("Warning during .onUnload: ", e$message)
  })
}
