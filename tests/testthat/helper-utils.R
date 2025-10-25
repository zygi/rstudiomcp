# Test utility functions

#' Skip test if not running in RStudio
skip_if_not_rstudio <- function() {
  if (!requireNamespace("rstudioapi", quietly = TRUE) || !rstudioapi::isAvailable()) {
    testthat::skip("Requires RStudio")
  }
}
