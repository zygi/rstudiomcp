#!/usr/bin/env python3
# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "mcp",
#   "pytest",
#   "pytest-asyncio",
# ]
# ///
"""
Integration test for RStudio MCP server.

This script tests the MCP server by connecting via streamable HTTP and
exercising all the tool endpoints using pytest.

Usage:
    Run with: uv run tests/test_integration.py
"""

import json
import sys
from pathlib import Path

import pytest
import pytest_asyncio
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client


def get_server_url():
    """Read the RStudio MCP server URL from .mcp.json"""
    config_path = Path(".mcp.json")
    if config_path.exists():
        try:
            with open(config_path) as f:
                config = json.load(f)
            if "mcpServers" in config and "rstudio" in config["mcpServers"]:
                return config["mcpServers"]["rstudio"]["url"]
        except Exception:
            pass
    return "http://127.0.0.1:16731/"


async def get_session():
    """Helper to create an MCP session"""
    url = get_server_url()
    return streamablehttp_client(url)


def extract_doc_id_from_insert(result_text):
    """Extract document ID from create_document result"""
    return result_text.split("ID:")[1].strip()


async def cleanup_document(session, doc_id):
    """Close a document without saving

    Args:
        session: MCP client session
        doc_id: Document ID to close
    """
    await session.call_tool("eval_r", {
        "code": f'rstudioapi::documentClose(id = "{doc_id}", save = FALSE)',
        "allow_reassign": True
    })


@pytest_asyncio.fixture(autouse=True)
async def clean_environment():
    """Clean the R environment and close all documents before each test"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            # Remove all objects from global environment (except MCP server reference)
            await session.call_tool("eval_r", {
                "code": """
                # Remove everything except .rstudiomcp_server
                objs_to_remove <- setdiff(ls(all.names = TRUE), ".rstudiomcp_server")
                rm(list = objs_to_remove)
                """,
                "allow_reassign": True
            })
            # Close all open documents by repeatedly closing the active document
            await session.call_tool("eval_r", {
                "code": """
                tryCatch({
                  # Close up to 20 documents (safety limit)
                  for (i in 1:20) {
                    ctx <- rstudioapi::getActiveDocumentContext()
                    if (is.null(ctx$id) || ctx$id == "#console" || !nzchar(ctx$id)) {
                      break
                    }
                    rstudioapi::documentClose(id = ctx$id, save = FALSE)
                  }
                }, error = function(e) invisible())
                """,
                "allow_reassign": True
            })
    yield
    # Teardown: could clean up here if needed


@pytest.mark.asyncio
async def test_list_tools():
    """Test listing available tools"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()
            tools = await session.list_tools()
            assert len(tools.tools) == 13

            tool_names = [tool.name for tool in tools.tools]
            expected_tools = [
                "eval_r", "list_environments", "list_objects", "get_object",
                "get_console_history", "get_active_document",
                "create_document", "open_document_file",
                "insert_text", "replace_text_range", "source_active_document",
                "get_current_plot", "get_latest_viewer_content"
            ]
            for expected in expected_tools:
                assert expected in tool_names


@pytest.mark.asyncio
async def test_eval_r_basic():
    """Test basic R code execution"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            result = await session.call_tool("eval_r", {
                "code": "integration_test_var <- 42 + 8"
            })
            assert result.content[0].type == "text"

            # Verify variable was created
            result = await session.call_tool("list_objects", {})
            assert "integration_test_var" in result.content[0].text


@pytest.mark.asyncio
async def test_eval_r_allow_reassign_protection():
    """Test that eval_r prevents reassignment by default"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a variable
            await session.call_tool("eval_r", {"code": "test_reassign_var <- 10"})

            # Try to reassign without permission
            with pytest.raises(Exception) as exc_info:
                await session.call_tool("eval_r", {
                    "code": "test_reassign_var <- 20",
                    "allow_reassign": False
                })
            assert "overwrite existing variable" in str(exc_info.value)


@pytest.mark.asyncio
async def test_eval_r_allow_reassign_true():
    """Test that eval_r allows reassignment with allow_reassign=true"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a variable
            await session.call_tool("eval_r", {"code": "test_reassign_ok <- 10"})

            # Reassign with permission
            result = await session.call_tool("eval_r", {
                "code": "test_reassign_ok <- 20",
                "allow_reassign": True
            })
            assert result.content[0].type == "text"


@pytest.mark.asyncio
async def test_list_environments():
    """Test listing R environments"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            result = await session.call_tool("list_environments", {})
            envs = result.content[0].text.split('\n')

            assert ".GlobalEnv" in envs
            assert "package:base" in envs


@pytest.mark.asyncio
async def test_list_objects():
    """Test listing objects in environment"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create some test objects
            await session.call_tool("eval_r", {
                "code": "obj1 <- 1; obj2 <- 2; obj3 <- 3"
            })

            result = await session.call_tool("list_objects", {})
            objects = result.content[0].text

            assert "obj1" in objects
            assert "obj2" in objects
            assert "obj3" in objects


@pytest.mark.asyncio
async def test_get_object():
    """Test getting object details"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a test data frame
            await session.call_tool("eval_r", {
                "code": "test_df <- data.frame(a = 1:3, b = c('x', 'y', 'z'))"
            })

            result = await session.call_tool("get_object", {"name": "test_df"})
            obj_text = result.content[0].text

            assert "data.frame" in obj_text
            assert "3 obs" in obj_text


@pytest.mark.asyncio
async def test_get_console_history():
    """Test getting console history"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            result = await session.call_tool("get_console_history", {"max_lines": 5})
            assert result.content[0].type == "text"
            # History might be empty, just check it doesn't error


@pytest.mark.asyncio
async def test_create_document():
    """Test creating a new document (untitled)"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            result = await session.call_tool("create_document", {
                "text": "# Test document\nprint('Hello')\n"
            })

            response_text = result.content[0].text
            assert "Created new document with ID:" in response_text

            # Extract document ID
            doc_id = extract_doc_id_from_insert(response_text)

            # Verify it's active and we can read it
            result = await session.call_tool("get_active_document", {})
            contents = result.content[0].text
            assert "ID:" in contents
            assert "Path: <untitled>" in contents
            assert "# Test document" in contents
            assert "print('Hello')" in contents

            # Clean up
            await cleanup_document(session, doc_id)


@pytest.mark.asyncio
async def test_create_document_with_path():
    """Test creating a new document with a file path"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a temporary file path
            temp_file = "test_create_with_path.R"
            result = await session.call_tool("eval_r", {
                "code": f'file.path(tempdir(), "{temp_file}")',
                "allow_reassign": True
            })
            temp_path = result.content[0].text.strip().replace('[1] "', '').replace('"', '')

            # Create a document with path
            result = await session.call_tool("create_document", {
                "text": "# Saved test\nx <- 42\nprint(x)",
                "path": temp_path
            })

            response_text = result.content[0].text
            assert "Created new document at:" in response_text
            assert temp_file in response_text

            # Extract document ID
            doc_id = extract_doc_id_from_insert(response_text)

            # Verify it's active and has a proper path
            result = await session.call_tool("get_active_document", {})
            contents = result.content[0].text
            assert "ID:" in contents
            assert temp_file in contents  # Path should contain filename
            assert "# Saved test" in contents
            assert "x <- 42" in contents

            # Verify file exists on disk
            result = await session.call_tool("eval_r", {
                "code": f'file.exists("{temp_path}")'
            })
            assert "TRUE" in result.content[0].text

            # Clean up
            await cleanup_document(session, doc_id)
            await session.call_tool("eval_r", {
                "code": f'unlink("{temp_path}")',
                "allow_reassign": True
            })


@pytest.mark.asyncio
async def test_insert_text_active_document():
    """Test inserting text into the active document"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a document
            result = await session.call_tool("create_document", {
                "text": "# Original content"
            })
            doc_id = extract_doc_id_from_insert(result.content[0].text)

            # Insert more text
            await session.call_tool("insert_text", {
                "text": "\nx <- 42"
            })

            # Verify content was inserted
            result = await session.call_tool("get_active_document", {})
            contents = result.content[0].text
            assert "ID:" in contents
            assert "# Original content" in contents
            assert "x <- 42" in contents

            # Clean up
            await cleanup_document(session, doc_id)


@pytest.mark.asyncio
async def test_open_document_file():
    """Test opening a saved document file"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a temporary R file
            temp_file = "test_open_script.R"
            result = await session.call_tool("eval_r", {
                "code": f'''
                temp_path <- file.path(tempdir(), "{temp_file}")
                writeLines(c("# Saved test", "y <- 100", "print(y)"), temp_path)
                temp_path
                ''',
                "allow_reassign": True
            })
            temp_path = result.content[0].text.strip().replace('[1] "', '').replace('"', '')

            # Open the file
            result = await session.call_tool("open_document_file", {
                "file_path": temp_path
            })

            assert "Opened document:" in result.content[0].text
            assert temp_file in result.content[0].text

            # Verify it's active and we can read it
            result = await session.call_tool("get_active_document", {})
            contents = result.content[0].text
            assert "ID:" in contents
            assert "Path:" in contents
            assert temp_file in contents  # Filename should be in path
            assert "# Saved test" in contents
            assert "y <- 100" in contents

            # Clean up
            await session.call_tool("eval_r", {
                "code": f'unlink("{temp_path}")',
                "allow_reassign": True
            })


@pytest.mark.asyncio
async def test_replace_text_range_active():
    """Test replacing text in the active document"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a document
            result = await session.call_tool("create_document", {
                "text": "old_value <- 123"
            })
            doc_id = extract_doc_id_from_insert(result.content[0].text)

            # Replace text
            result = await session.call_tool("replace_text_range", {
                "old_string": "old_value <- 123",
                "new_string": "new_value <- 456"
            })

            assert "Text replaced successfully" in result.content[0].text

            # Verify replacement
            result = await session.call_tool("get_active_document", {})
            assert "new_value <- 456" in result.content[0].text

            # Clean up
            await cleanup_document(session, doc_id)


@pytest.mark.asyncio
async def test_source_active_document():
    """Test sourcing the active document"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a document with R code
            result = await session.call_tool("create_document", {
                "text": "source_test_var <- 999"
            })
            doc_id = extract_doc_id_from_insert(result.content[0].text)

            # Source the active document
            result = await session.call_tool("source_active_document", {})

            assert "Sourced document:" in result.content[0].text
            assert "source_test_var <- 999" in result.content[0].text

            # Verify variable was created
            result = await session.call_tool("list_objects", {})
            assert "source_test_var" in result.content[0].text

            # Clean up
            await cleanup_document(session, doc_id)


@pytest.mark.asyncio
async def test_source_active_document_partial():
    """Test sourcing only specific lines of the active document"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a document with multiple lines
            result = await session.call_tool("create_document", {
                "text": "var_a <- 1\nvar_b <- 2\nvar_c <- 3\nvar_d <- 4"
            })
            doc_id = extract_doc_id_from_insert(result.content[0].text)

            # Source only lines 2-3
            result = await session.call_tool("source_active_document", {
                "start_line": 2,
                "end_line": 3
            })

            assert "(lines 2-3)" in result.content[0].text
            assert "var_b <- 2" in result.content[0].text
            assert "var_c <- 3" in result.content[0].text

            # Verify only var_b and var_c were created
            result = await session.call_tool("list_objects", {})
            objects = result.content[0].text
            assert "var_b" in objects
            assert "var_c" in objects
            # var_a and var_d should not exist
            assert "var_a" not in objects
            assert "var_d" not in objects

            # Verify that lines 2-3 are now selected in the editor
            result = await session.call_tool("eval_r", {
                "code": """
                ctx <- rstudioapi::getSourceEditorContext()
                sel <- ctx$selection[[1]]$range
                list(start = sel$start[['row']], end = sel$end[['row']])
                """
            })
            selection_info = result.content[0].text
            # Should show that rows 2-3 are selected
            assert "start" in selection_info
            assert "2" in selection_info  # Start line should be 2
            assert "3" in selection_info  # End line should be 3

            # Clean up
            await cleanup_document(session, doc_id)


@pytest.mark.asyncio
async def test_get_current_plot():
    """Test capturing a plot"""
    async with await get_session() as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            await session.initialize()

            # Create a simple plot
            await session.call_tool("eval_r", {"code": "plot(1:10, 1:10)"})

            result = await session.call_tool("get_current_plot", {
                "width": 400,
                "height": 300,
                "format": "png"
            })

            assert result.content[0].type == "image"
            assert len(result.content[0].data) > 100  # Should have substantial base64 data


if __name__ == "__main__":
    # Run pytest on this file when executed directly
    sys.exit(pytest.main([__file__, "-v"]))
