#!/bin/bash
set -e

echo "Setting up ClaudeTheArtist Python environment..."

# Define installation directory
INSTALL_DIR="$HOME/Documents/ClaudeTheArtist"
UV_DIR="$INSTALL_DIR/.uv"
UV_BIN="$UV_DIR/uv"

# Create directory if it doesn't exist
mkdir -p "$UV_DIR"

# Check if uv is already installed in our target location
if [ -f "$UV_BIN" ]; then
    echo "✓ uv already installed at $UV_BIN"
else
    # Check if uv exists in PATH
    if command -v uv &> /dev/null; then
        echo "Found uv in PATH, copying to $UV_BIN..."
        cp "$(which uv)" "$UV_BIN"
        echo "✓ uv copied successfully"
    else
        echo "Installing uv..."
        # Install to default location first
        curl -LsSf https://astral.sh/uv/install.sh | sh

        # Copy from default location to our target
        if [ -f "$HOME/.local/bin/uv" ]; then
            cp "$HOME/.local/bin/uv" "$UV_BIN"
            echo "✓ uv installed successfully"
        else
            echo "Error: Could not find uv after installation"
            exit 1
        fi
    fi
fi

# Get the project directory (where this script is located)
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Installing Python dependencies..."
cd "$PROJECT_DIR"
"$UV_BIN" sync

echo ""
echo "✓ Setup complete!"
echo "  - uv installed at: $UV_BIN"
echo "  - Python dependencies installed"
