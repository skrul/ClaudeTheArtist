#!/usr/bin/env python3
"""
Demo client that uses the claude_sdk_wrapper.py subprocess interface.
"""

import asyncio
import json
import sys
from asyncio.subprocess import Process


class WrapperClient:
    """Client for interacting with claude_sdk_wrapper.py subprocess."""

    def __init__(self):
        self.process: Process | None = None

    async def start(self):
        """Start the wrapper subprocess."""
        self.process = await asyncio.create_subprocess_exec(
            "uv", "run", "claude_sdk_wrapper.py",
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        print("Started claude_sdk_wrapper subprocess")

    async def send_command(self, command: dict):
        """Send a JSON command to the wrapper."""
        if not self.process or not self.process.stdin:
            raise RuntimeError("Process not started")

        command_json = json.dumps(command) + "\n"
        self.process.stdin.write(command_json.encode())
        await self.process.stdin.drain()
        print(f"Sent: {command}")

    async def read_response(self):
        """Read a single JSON response from the wrapper."""
        if not self.process or not self.process.stdout:
            raise RuntimeError("Process not started")

        line = await self.process.stdout.readline()
        if not line:
            return None

        response = json.loads(line.decode().strip())
        return response

    async def stream_responses(self, stop_event: asyncio.Event):
        """Continuously stream responses until stop_event is set."""
        while not stop_event.is_set():
            try:
                response = await asyncio.wait_for(self.read_response(), timeout=0.5)
                if response:
                    # Pretty print AssistantMessages, show others as JSON
                    if response.get("type") == "message" and response.get("message_type") == "AssistantMessage":
                        content = response.get("content", [])
                        for block in content:
                            if block.get("type") == "text":
                                print(f"\n💬 Claude: {block['text']}\n")
                    elif response.get("type") == "response":
                        # Command responses - show briefly
                        print(f"✓ {response.get('command')} succeeded")
                    # Silently ignore SystemMessage and ResultMessage for cleaner output
                else:
                    # EOF or no more data
                    break
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                print(f"Error reading response: {e}")
                break

    async def close(self):
        """Close the wrapper subprocess."""
        if self.process and self.process.stdin:
            self.process.stdin.close()
            await self.process.wait()
        print("Closed claude_sdk_wrapper subprocess")


async def main():
    """Demonstrate using the wrapper client."""
    client = WrapperClient()

    try:
        # Start the wrapper
        await client.start()

        # Create the Claude client (automatically connects in streaming mode)
        # Use a simple prompt to get a quick response
        print("Creating Claude client...")
        await client.send_command({
            "command": "create_client",
            "initial_prompt": "What is 2 + 2? Please answer very briefly."
        })
        await client.read_response()  # Read create_client success response
        print("✓ Client created\n")

        # Start streaming responses in background
        stop_streaming = asyncio.Event()
        stream_task = asyncio.create_task(client.stream_responses(stop_streaming))

        # Wait for first turn to complete
        print("Waiting for first response...")
        await asyncio.sleep(4)

        # Send another query
        print("\nSending second query...")
        await client.send_command({
            "command": "query",
            "prompt": "What is 10 + 5?"
        })

        # Wait for second response
        print("Waiting for second response...")
        await asyncio.sleep(6)

        # Disconnect
        print("\nDisconnecting...")
        await client.send_command({"command": "disconnect"})
        await asyncio.sleep(1)

        # Stop streaming and cleanup
        stop_streaming.set()
        await stream_task

    except KeyboardInterrupt:
        print("\nInterrupted by user")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        await client.close()


if __name__ == "__main__":
    asyncio.run(main())
