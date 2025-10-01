#!/usr/bin/env python3
"""
JSON-based stdin/stdout interface for Claude Agent SDK.
Provides a streaming interface for other applications to interact with Claude.
"""

import os
import sys

# CRITICAL: Remove API keys before importing SDK to ensure CLI auth is used
# This must happen BEFORE any claude_agent_sdk imports
for key in ['ANTHROPIC_API_KEY', 'CLAUDE_API_KEY', 'ANTHROPIC_AUTH_TOKEN']:
    os.environ.pop(key, None)

from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    AssistantMessage,
    TextBlock,
    ToolUseBlock,
    ToolResultBlock,
    tool,
    create_sdk_mcp_server,
)
import asyncio
import json
from typing import Optional, Dict, Any, List


class ClaudeSDKWrapper:
    """Wrapper providing JSON stdin/stdout interface for Claude Agent SDK."""

    def __init__(self):
        self.client: Optional[ClaudeSDKClient] = None
        self.receive_task: Optional[asyncio.Task] = None
        self.tool_result_futures: Dict[str, asyncio.Future] = {}  # tool_use_id -> Future

    def write_output(self, data: Dict[str, Any]):
        """Write JSON output to stdout."""
        print(json.dumps(data), flush=True)

    async def receive_messages(self):
        """Continuously receive messages from client and write to stdout."""
        if not self.client:
            return

        try:
            async for message in self.client.receive_messages():
                message_data = {
                    "type": "message",
                    "message_type": message.__class__.__name__,
                }

                if isinstance(message, AssistantMessage):
                    content = []
                    for block in message.content:
                        if isinstance(block, TextBlock):
                            content.append({"type": "text", "text": block.text})
                        elif isinstance(block, ToolUseBlock):
                            content.append({
                                "type": "tool_use",
                                "id": block.id,
                                "name": block.name,
                                "input": block.input,
                            })
                        elif isinstance(block, ToolResultBlock):
                            content.append({
                                "type": "tool_result",
                                "tool_use_id": block.tool_use_id,
                                "content": block.content,
                                "is_error": block.is_error,
                            })
                    message_data["content"] = content
                else:
                    # Generic message handling
                    message_data["data"] = str(message)

                self.write_output(message_data)
        except Exception as e:
            self.write_output({"type": "error", "error": str(e)})

    def create_tool_handler(self, tool_name: str, tool_description: str, tool_input_schema: Dict[str, Any]):
        """Dynamically create a tool handler that emits to stdout and waits for external result."""
        @tool(tool_name, tool_description, tool_input_schema)
        async def generic_tool_handler(args: Dict[str, Any]):
            # Generate a unique ID for this tool invocation
            tool_use_id = f"tool_{id(args)}_{asyncio.get_event_loop().time()}"

            # Emit tool invocation to stdout
            self.write_output({
                "type": "tool_invocation",
                "tool_use_id": tool_use_id,
                "name": tool_name,
                "input": args
            })

            # Create a future to wait for the external result
            future = asyncio.Future()
            self.tool_result_futures[tool_use_id] = future

            # Wait for external result
            try:
                result = await future
                return {
                    "content": [
                        {"type": "text", "text": result.get("content", "")}
                    ],
                    "isError": result.get("is_error", False)
                }
            finally:
                # Clean up
                self.tool_result_futures.pop(tool_use_id, None)

        return generic_tool_handler

    async def handle_create_client(self, options: Dict[str, Any], initial_prompt: Optional[str] = None, tools: Optional[List[Dict[str, Any]]] = None):
        """Create the Claude SDK client and connect in streaming mode."""
        try:
            # Convert dict options to ClaudeAgentOptions
            agent_options = ClaudeAgentOptions(**options) if options else ClaudeAgentOptions()

            # If tools are provided, create an SDK MCP server with them
            if tools:
                tool_handlers = []
                allowed_tools = []

                for tool_def in tools:
                    tool_name = tool_def["name"]
                    tool_description = tool_def["description"]
                    tool_input_schema = tool_def["input_schema"]

                    handler = self.create_tool_handler(tool_name, tool_description, tool_input_schema)
                    tool_handlers.append(handler)
                    allowed_tools.append(f"mcp__external_tools__{tool_name}")

                # Create SDK MCP server with all tools
                server = create_sdk_mcp_server(
                    name="external_tools",
                    version="1.0.0",
                    tools=tool_handlers
                )

                # Add MCP server to agent options
                if not hasattr(agent_options, 'mcp_servers') or agent_options.mcp_servers is None:
                    agent_options.mcp_servers = {}
                agent_options.mcp_servers["external_tools"] = server

                # Set allowed tools
                if not hasattr(agent_options, 'allowed_tools') or agent_options.allowed_tools is None:
                    agent_options.allowed_tools = []
                agent_options.allowed_tools.extend(allowed_tools)

            self.client = ClaudeSDKClient(agent_options)

            # Always connect in streaming mode (required for the wrapper to work)
            await self.client.connect()

            # Start receiving messages in background
            self.receive_task = asyncio.create_task(self.receive_messages())

            self.write_output({"type": "response", "command": "create_client", "success": True})

            # If an initial prompt was provided, send it now
            if initial_prompt:
                await self.client.query(initial_prompt)
        except Exception as e:
            self.write_output({"type": "error", "command": "create_client", "error": str(e)})

    async def handle_query(self, prompt: str):
        """Send a query to the client."""
        if not self.client:
            self.write_output({"type": "error", "command": "query", "error": "Client not created"})
            return

        try:
            await self.client.query(prompt)
            self.write_output({"type": "response", "command": "query", "success": True})
        except Exception as e:
            self.write_output({"type": "error", "command": "query", "error": str(e)})

    async def handle_interrupt(self):
        """Send interrupt signal to the client."""
        if not self.client:
            self.write_output({"type": "error", "command": "interrupt", "error": "Client not created"})
            return

        try:
            await self.client.interrupt()
            self.write_output({"type": "response", "command": "interrupt", "success": True})
        except Exception as e:
            self.write_output({"type": "error", "command": "interrupt", "error": str(e)})

    async def handle_disconnect(self):
        """Disconnect the client."""
        if not self.client:
            self.write_output({"type": "error", "command": "disconnect", "error": "Client not created"})
            return

        try:
            # Cancel the receive task if it's running
            if self.receive_task and not self.receive_task.done():
                self.receive_task.cancel()
                try:
                    await self.receive_task
                except asyncio.CancelledError:
                    pass

            await self.client.disconnect()
            self.write_output({"type": "response", "command": "disconnect", "success": True})
        except Exception as e:
            self.write_output({"type": "error", "command": "disconnect", "error": str(e)})

    async def handle_tool_result(self, tool_use_id: str, content: str, is_error: bool = False):
        """Receive a tool result from the external caller and resolve the waiting future."""
        try:
            future = self.tool_result_futures.get(tool_use_id)
            if future and not future.done():
                future.set_result({
                    "content": content,
                    "is_error": is_error
                })
                self.write_output({"type": "response", "command": "tool_result", "success": True})
            else:
                self.write_output({"type": "error", "command": "tool_result", "error": f"No pending tool invocation with ID: {tool_use_id}"})
        except Exception as e:
            self.write_output({"type": "error", "command": "tool_result", "error": str(e)})

    async def process_command(self, command_data: Dict[str, Any]):
        """Process a single command from stdin."""
        command = command_data.get("command")

        if command == "create_client":
            await self.handle_create_client(
                command_data.get("options"),
                command_data.get("initial_prompt"),
                command_data.get("tools")
            )
        elif command == "query":
            await self.handle_query(command_data.get("prompt"))
        elif command == "interrupt":
            await self.handle_interrupt()
        elif command == "disconnect":
            await self.handle_disconnect()
        elif command == "tool_result":
            await self.handle_tool_result(
                command_data.get("tool_use_id"),
                command_data.get("content"),
                command_data.get("is_error", False)
            )
        else:
            self.write_output({"type": "error", "error": f"Unknown command: {command}"})

    async def run(self):
        """Main loop: read commands from stdin and process them."""
        loop = asyncio.get_event_loop()

        # Read from stdin in a non-blocking way
        while True:
            try:
                # Read line from stdin
                line = await loop.run_in_executor(None, sys.stdin.readline)
                if not line:
                    # EOF reached
                    break

                line = line.strip()
                if not line:
                    continue

                # Parse JSON command
                try:
                    command_data = json.loads(line)
                    await self.process_command(command_data)
                except json.JSONDecodeError as e:
                    self.write_output({"type": "error", "error": f"Invalid JSON: {str(e)}"})

            except Exception as e:
                self.write_output({"type": "error", "error": str(e)})
                break

        # Clean up on exit
        if self.receive_task and not self.receive_task.done():
            self.receive_task.cancel()
        if self.client:
            await self.client.disconnect()


async def main():
    wrapper = ClaudeSDKWrapper()
    await wrapper.run()


if __name__ == "__main__":
    asyncio.run(main())
