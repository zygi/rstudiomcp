# Utility functions

#' Detect variable assignments in R code (supports <-, =, ->, <<-, assign())
#' @keywords internal
detect_assignments <- function(code_text) {
  expr <- tryCatch(parse(text = code_text), error = function(e) {
    return(character(0))
  })
  assignments <- character(0)

  walk_expr <- function(e) {
    if (!is.call(e)) {
      return()
    }

    op <- as.character(e[[1]])

    if (op %in% c("<-", "=", "<<-") && is.name(e[[2]])) {
      assignments <<- c(assignments, as.character(e[[2]]))
    } else if (op == "->" && is.name(e[[3]])) {
      assignments <<- c(assignments, as.character(e[[3]]))
    } else if (op == "assign" && length(e) >= 2) {
      var <- e[[2]]
      if (is.character(var) || is.name(var)) {
        assignments <<- c(assignments, if (is.character(var)) var else as.character(var))
      }
    }

    if (length(e) > 1) {
      for (i in 2:length(e)) walk_expr(e[[i]])
    }
  }

  for (i in seq_along(expr)) walk_expr(expr[[i]])
  unique(assignments)
}
