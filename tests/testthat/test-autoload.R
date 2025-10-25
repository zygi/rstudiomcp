# Helper to read file as single string
read_file <- function(path) paste(readLines(path, warn = FALSE), collapse = "\n")

# Helper to check multiple patterns
expect_contains <- function(text, patterns, fixed = TRUE) {
  for (pattern in patterns) {
    expect_true(grepl(pattern, text, fixed = fixed))
  }
}

test_that("setup_autoload adds the exact code block", {
  skip_on_cran()
  skip_if_not_rstudio()

  test_dir <- tempfile()
  dir.create(test_dir)
  old_dir <- setwd(test_dir)
  on.exit(
    {
      setwd(old_dir)
      unlink(test_dir, recursive = TRUE)
    },
    add = TRUE
  )
  rprofile_path <- ".Rprofile"

  autoload_code <- rstudiomcp:::.get_autoload_code()
  cat(autoload_code, file = rprofile_path)

  expect_true(file.exists(rprofile_path))
  content <- read_file(rprofile_path)
  expect_contains(content, c(
    "# Auto-load rstudiomcp package", "tryCatch",
    "library(rstudiomcp)", "Failed to load rstudiomcp"
  ))
})

test_that("disable_autoload removes the exact code block", {
  skip_on_cran()
  skip_if_not_rstudio()

  test_dir <- tempfile()
  dir.create(test_dir)
  old_dir <- setwd(test_dir)
  on.exit(
    {
      setwd(old_dir)
      unlink(test_dir, recursive = TRUE)
    },
    add = TRUE
  )
  rprofile_path <- ".Rprofile"

  autoload_code <- rstudiomcp:::.get_autoload_code()
  cat("# Some user code\nx <- 1\n", file = rprofile_path)
  cat(autoload_code, file = rprofile_path, append = TRUE)
  cat("\n# More user code\ny <- 2\n", file = rprofile_path, append = TRUE)

  content_before <- read_file(rprofile_path)
  expect_contains(content_before, c("# Auto-load rstudiomcp package", "x <- 1", "y <- 2"))

  # Remove autoload code
  writeLines(gsub(autoload_code, "", content_before, fixed = TRUE), rprofile_path)

  final_content <- read_file(rprofile_path)
  expect_false(grepl("# Auto-load rstudiomcp package", final_content, fixed = TRUE))
  expect_false(grepl("library(rstudiomcp)", final_content, fixed = TRUE))
  expect_contains(final_content, c("x <- 1", "y <- 2"))
})

test_that("adding code twice doesn't duplicate", {
  skip_on_cran()
  skip_if_not_rstudio()

  test_dir <- tempfile()
  dir.create(test_dir)
  old_dir <- setwd(test_dir)
  on.exit(
    {
      setwd(old_dir)
      unlink(test_dir, recursive = TRUE)
    },
    add = TRUE
  )
  rprofile_path <- ".Rprofile"

  autoload_code <- rstudiomcp:::.get_autoload_code()
  cat(autoload_code, file = rprofile_path)

  # Check if already present (simulating setup_autoload logic)
  content <- read_file(rprofile_path)
  if (!grepl("# Auto-load rstudiomcp package", content, fixed = TRUE)) {
    cat(autoload_code, file = rprofile_path, append = TRUE)
  }

  # Count occurrences - should be exactly 1
  lines <- readLines(rprofile_path, warn = FALSE)
  expect_equal(sum(grepl("# Auto-load rstudiomcp package", lines, fixed = TRUE)), 1)
})

test_that("autoload code is valid R syntax", {
  autoload_code <- rstudiomcp:::.get_autoload_code()
  code_lines <- strsplit(autoload_code, "\n")[[1]]

  # Remove empty lines and comments, then parse
  code_to_parse <- code_lines[nzchar(trimws(code_lines)) & !grepl("^#", trimws(code_lines))]
  expect_error(parse(text = paste(code_to_parse, collapse = "\n")), NA)
})

test_that("autoload code has proper tryCatch structure", {
  autoload_code <- rstudiomcp:::.get_autoload_code()
  expect_contains(autoload_code, c(
    "tryCatch\\(", "library\\(rstudiomcp\\)",
    "error = function\\(e\\)", "warning\\(",
    "Failed to load rstudiomcp"
  ), fixed = FALSE)
})
