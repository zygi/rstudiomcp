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


@pytest_asyncio.fixture(scope="session")
async def mcp_session():
    """Fixture that provides an MCP client session connected to RStudio"""
    url = get_server_url()

    async with streamablehttp_client(url) as (read_stream, write_stream, _):
        async with ClientSession(read_stream, write_stream) as session:
            # Initialize
            await session.initialize()

            # Clean environment before tests
            await session.call_tool("eval_r", {
                "code": "rm(list = ls(all.names = TRUE))",
                "allow_reassign": True
            })

            yield session


@pytest.mark.asyncio
async def test_list_tools(mcp_session):
    """Test listing available tools"""
    tools = await mcp_session.list_tools()
    assert len(tools.tools) == 12

    tool_names = [tool.name for tool in tools.tools]
    expected_tools = [
        "eval_r", "list_environments", "list_objects", "get_object",
        "get_console_history", "list_open_documents", "get_document_contents",
        "insert_text", "replace_text_range", "source_document",
        "get_current_plot", "get_viewer_content"
    ]
    for expected in expected_tools:
        assert expected in tool_names


@pytest.mark.asyncio
async def test_eval_r_basic(mcp_session):
    """Test basic R code execution"""
    result = await mcp_session.call_tool("eval_r", {
        "code": "test_var <- 42 + 8"
    })
    assert result.content[0].type == "text"

    # Verify variable was created
    result = await mcp_session.call_tool("list_objects", {})
    assert "test_var" in result.content[0].text


@pytest.mark.asyncio
async def test_eval_r_allow_reassign_protection(mcp_session):
    """Test that eval_r prevents reassignment by default"""
    # Create a variable
    await mcp_session.call_tool("eval_r", {"code": "x <- 10"})

    # Try to reassign without permission
    with pytest.raises(Exception) as exc_info:
        await mcp_session.call_tool("eval_r", {
            "code": "x <- 20",
            "allow_reassign": False
        })
    assert "overwrite existing variable" in str(exc_info.value)


@pytest.mark.asyncio
async def test_eval_r_allow_reassign_true(mcp_session):
    """Test that eval_r allows reassignment with allow_reassign=true"""
    # Create a variable
    await mcp_session.call_tool("eval_r", {"code": "y <- 10"})

    # Reassign with permission
    result = await mcp_session.call_tool("eval_r", {
        "code": "y <- 20",
        "allow_reassign": True
    })
    assert result.content[0].type == "text"


@pytest.mark.asyncio
async def test_list_environments(mcp_session):
    """Test listing R environments"""
    result = await mcp_session.call_tool("list_environments", {})
    envs = result.content[0].text.split('\n')

    assert ".GlobalEnv" in envs
    assert "package:base" in envs


@pytest.mark.asyncio
async def test_list_objects(mcp_session):
    """Test listing objects in environment"""
    # Create some test objects
    await mcp_session.call_tool("eval_r", {
        "code": "obj1 <- 1; obj2 <- 2; obj3 <- 3"
    })

    result = await mcp_session.call_tool("list_objects", {})
    objects = result.content[0].text

    assert "obj1" in objects
    assert "obj2" in objects
    assert "obj3" in objects


@pytest.mark.asyncio
async def test_get_object(mcp_session):
    """Test getting object details"""
    # Create a test data frame
    await mcp_session.call_tool("eval_r", {
        "code": "test_df <- data.frame(a = 1:3, b = c('x', 'y', 'z'))"
    })

    result = await mcp_session.call_tool("get_object", {"name": "test_df"})
    obj_text = result.content[0].text

    assert "data.frame" in obj_text
    assert "3 obs" in obj_text


@pytest.mark.asyncio
async def test_get_console_history(mcp_session):
    """Test getting console history"""
    result = await mcp_session.call_tool("get_console_history", {"max_lines": 5})
    assert result.content[0].type == "text"
    # History might be empty, just check it doesn't error


@pytest.mark.asyncio
async def test_list_open_documents(mcp_session):
    """Test listing open documents"""
    result = await mcp_session.call_tool("list_open_documents", {})
    assert result.content[0].type == "text"
    # May show "(no open documents)" or list of documents


@pytest.mark.asyncio
async def test_insert_text_create_new(mcp_session):
    """Test creating a new document with insert_text"""
    result = await mcp_session.call_tool("insert_text", {
        "text": "# Test document\nprint('Hello')\n",
        "create_new": True
    })

    response_text = result.content[0].text
    assert "Created new document with ID:" in response_text

    # Extract document ID
    doc_id = response_text.split("ID:")[1].strip()

    # Verify document appears in list
    result = await mcp_session.call_tool("list_open_documents", {})
    assert doc_id in result.content[0].text


@pytest.mark.asyncio
async def test_insert_text_create_new_conflicts_with_file_path(mcp_session):
    """Test that create_new and file_path cannot be used together"""
    with pytest.raises(Exception) as exc_info:
        await mcp_session.call_tool("insert_text", {
            "text": "test",
            "create_new": True,
            "file_path": "/some/path.R"
        })
    assert "Cannot specify both" in str(exc_info.value)


@pytest.mark.asyncio
async def test_get_current_plot(mcp_session):
    """Test capturing a plot"""
    # Create a simple plot
    await mcp_session.call_tool("eval_r", {"code": "plot(1:10, 1:10)"})

    result = await mcp_session.call_tool("get_current_plot", {
        "width": 400,
        "height": 300,
        "format": "png"
    })

    assert result.content[0].type == "image"
    assert len(result.content[0].data) > 100  # Should have substantial base64 data


if __name__ == "__main__":
    # Run pytest on this file when executed directly
    sys.exit(pytest.main([__file__, "-v"]))
