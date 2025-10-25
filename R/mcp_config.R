# MCP Configuration File Management

# Helper: Create empty JSON object (not array)
empty_obj <- function() {
  obj <- list()
  names(obj) <- character(0)
  obj
}

# Helper: Write config to file
write_config <- function(config, path) {
  jsonlite::write_json(config, path, auto_unbox = TRUE, pretty = TRUE)
}

#' @export
add_to_mcp_config <- function() {
  path <- file.path(getwd(), ".mcp.json")

  config <- if (file.exists(path)) {
    cfg <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    if (is.null(cfg$mcpServers)) cfg$mcpServers <- empty_obj()
    cfg
  } else {
    list(mcpServers = empty_obj())
  }

  config$mcpServers$rstudio <- list(
    type = "http",
    url = paste0("http://127.0.0.1:", get_mcp_port())
  )

  write_config(config, path)
  message("Added RStudio MCP server to ", path)
  invisible(TRUE)
}

#' @export
remove_from_mcp_config <- function() {
  path <- file.path(getwd(), ".mcp.json")
  if (!file.exists(path)) return(invisible(FALSE))

  config <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (is.null(config$mcpServers$rstudio)) return(invisible(FALSE))

  config$mcpServers$rstudio <- NULL
  if (length(config$mcpServers) == 0) config$mcpServers <- empty_obj()

  write_config(config, path)
  message("Removed RStudio MCP server from ", path)
  invisible(TRUE)
}
