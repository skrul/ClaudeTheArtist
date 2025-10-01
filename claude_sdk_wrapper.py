#!/usr/bin/env python3
"""
JSON-based stdin/stdout interface for Claude Agent SDK.
Provides a streaming interface for other applications to interact with Claude.
"""

from claude_agent_sdk import (
    ClaudeSDKClient,
    ClaudeAgentOptions,
    AssistantMessage,
    TextBlock,
    ToolUseBlock,
    ToolResultBlock,
)
import asyncio
import json
import sys
from typing import Optional, Dict, Any


class ClaudeSDKWrapper:
    """Wrapper providing JSON stdin/stdout interface for Claude Agent SDK."""

    def __init__(self):
        self.client: Optional[ClaudeSDKClient] = None
        self.receive_task: Optional[asyncio.Task] = None

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

    async def handle_create_client(self, options: Dict[str, Any], initial_prompt: Optional[str] = None):
        """Create the Claude SDK client and connect in streaming mode."""
        try:
            # Convert dict options to ClaudeAgentOptions
            agent_options = ClaudeAgentOptions(**options) if options else ClaudeAgentOptions()
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

    async def process_command(self, command_data: Dict[str, Any]):
        """Process a single command from stdin."""
        command = command_data.get("command")

        if command == "create_client":
            await self.handle_create_client(
                command_data.get("options"),
                command_data.get("initial_prompt")
            )
        elif command == "query":
            await self.handle_query(command_data.get("prompt"))
        elif command == "interrupt":
            await self.handle_interrupt()
        elif command == "disconnect":
            await self.handle_disconnect()
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
