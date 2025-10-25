test_that("detect_assignments handles basic <- assignment", {
  result <- detect_assignments("x <- 5")
  expect_equal(result, "x")
})

test_that("detect_assignments handles = assignment", {
  result <- detect_assignments("y = 10")
  expect_equal(result, "y")
})

test_that("detect_assignments handles -> assignment", {
  result <- detect_assignments("20 -> z")
  expect_equal(result, "z")
})

test_that("detect_assignments handles <<- assignment", {
  result <- detect_assignments("a <<- 100")
  expect_equal(result, "a")
})

test_that("detect_assignments handles assign() function", {
  result <- detect_assignments('assign("myvar", 42)')
  expect_equal(result, "myvar")
})

test_that("detect_assignments handles multiple assignments", {
  code <- "x <- 1; y <- 2; z <- 3"
  result <- detect_assignments(code)
  expect_setequal(result, c("x", "y", "z"))
})

test_that("detect_assignments handles nested assignments", {
  code <- "x <- y <- 5"
  result <- detect_assignments(code)
  expect_setequal(result, c("x", "y"))
})

test_that("detect_assignments returns empty for code with no assignments", {
  result <- detect_assignments("print(42)")
  expect_equal(result, character(0))
})

test_that("detect_assignments handles complex expressions with assignments", {
  code <- "result <- data.frame(x = 1:10, y = rnorm(10))"
  result <- detect_assignments(code)
  expect_equal(result, "result")
})

test_that("detect_assignments deduplicates variable names", {
  code <- "x <- 1; x <- 2; x <- 3"
  result <- detect_assignments(code)
  expect_equal(result, "x")
  expect_equal(length(result), 1)
})

test_that("detect_assignments handles function definitions", {
  code <- "my_func <- function(x) { y <- x + 1; y }"
  result <- detect_assignments(code)
  # Should detect both my_func and y
  expect_setequal(result, c("my_func", "y"))
})

test_that("detect_assignments handles invalid/unparseable code", {
  result <- detect_assignments("this is not valid R code {{{")
  expect_equal(result, character(0))
})

test_that("detect_assignments handles mixed operators", {
  code <- "a <- 1; 2 -> b; c = 3; assign('d', 4)"
  result <- detect_assignments(code)
  expect_setequal(result, c("a", "b", "c", "d"))
})

test_that("detect_assignments ignores assignments in function arguments", {
  code <- "plot(x = 1:10, y = 1:10)"
  result <- detect_assignments(code)
  # Should be empty - these are named arguments, not assignments
  expect_equal(result, character(0))
})

test_that("detect_assignments handles assignment in if statement", {
  code <- "if (TRUE) { x <- 5 } else { y <- 10 }"
  result <- detect_assignments(code)
  expect_setequal(result, c("x", "y"))
})
