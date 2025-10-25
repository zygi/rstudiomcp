test_that("kill_process_on_port detects current process and refuses to kill it", {
  skip_on_cran()

  # Choose a random high port to avoid conflicts
  test_port <- sample(30000:40000, 1)

  # Helper function to check if port is in use (OS-level)
  is_port_in_use <- function(port) {
    os_type <- Sys.info()["sysname"]

    if (os_type == "Windows") {
      cmd <- paste0('cmd /c "netstat -ano | findstr :', port, '"')
      result <- suppressWarnings(system(cmd, intern = TRUE))
      # Check if we got output with LISTENING
      if (length(result) > 0) {
        any(grepl("LISTENING", result))
      } else {
        FALSE
      }
    } else {
      # macOS/Linux
      cmd <- paste0("lsof -ti:", port)
      result <- suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE))
      length(result) > 0 && nzchar(result[1])
    }
  }

  # Step 1: Confirm port is free initially
  expect_false(is_port_in_use(test_port),
    info = paste("Port", test_port, "should be free initially")
  )

  # Step 2: Create a simple httpuv server on the test port in the CURRENT process
  test_server <- httpuv::startServer(
    host = "127.0.0.1",
    port = test_port,
    app = list(
      call = function(req) {
        list(status = 200L, body = "test")
      }
    )
  )

  # Give the server a moment to start
  Sys.sleep(0.5)

  # Step 3: Confirm the port is now in use
  expect_true(is_port_in_use(test_port),
    info = paste("Port", test_port, "should be in use after starting server")
  )

  # Step 4: Try to kill the process - should detect it's the current process and refuse
  result <- kill_process_on_port(test_port, ask_confirmation = FALSE)

  # Should return FALSE because it refused to kill the current process
  expect_false(result, info = "Should return FALSE when refusing to kill current process")

  # Step 5: Port should still be in use (we didn't kill ourselves)
  expect_true(is_port_in_use(test_port),
    info = paste("Port", test_port, "should still be in use (process not killed)")
  )

  # Cleanup: properly stop the server
  httpuv::stopServer(test_server)
  Sys.sleep(0.5)

  # Step 6: Confirm port is free after proper cleanup
  expect_false(is_port_in_use(test_port),
    info = paste("Port", test_port, "should be free after stopServer()")
  )
})

test_that("kill_process_on_port returns TRUE when port is not in use", {
  skip_on_cran()

  # Choose a random high port that's unlikely to be in use
  test_port <- sample(40000:50000, 1)

  # Call on a free port should return TRUE (nothing to kill)
  result <- kill_process_on_port(test_port, ask_confirmation = FALSE)

  expect_true(result, info = "Should return TRUE when no process is using the port")
})
