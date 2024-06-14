#!/bin/bash

# Function to sync the virtual environment
venvsync() {
    local venv_name=$1

    if [ -z "$venv_name" ]; then
        echo "Usage: venv-sync <venvname>"
        return 1
    fi

    local workspace_path="$WORKSPACE/environments/python/$venv_name"
    local source_path="/opt/environments/python/$venv_name"
    local archive_path="$WORKSPACE/environments/python/${venv_name}.tar"

    if [ -d "$workspace_path" ]; then
        echo "Error: Directory $workspace_path already exists."
        return 1
    fi

    if [ ! -d "$source_path" ]; then
        echo "Error: Source directory $source_path does not exist."
        return 1
    fi

    # Create tar archive (no compression)
    tar -cf "$archive_path" -C "/opt/environments/python" "$venv_name" --no-same-owner --no-same-permissions
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create tar archive."
        return 1
    fi

    # Extract the tar archive
    mkdir -p "$workspace_path"
    tar -xf "$archive_path" -C "$workspace_path" --strip-components=1 --keep-newer-files --no-same-owner --no-same-permissions
    if [ $? -ne 0 ]; then
        echo "Error: Failed to extract tar archive."
        return 1
    fi

    # Update the paths in the virtual environment
    find "$workspace_path" -type f -name '*.pth' -exec sed -i "s|/opt/environments/python/$venv_name|$workspace_path|g" {} +
    find "$workspace_path/bin" -type f -exec sed -i "s|/opt/environments/python/$venv_name|$workspace_path|g" {} +

    # Remove the tar file
    rm -f "$archive_path"

    echo "Virtual environment '$venv_name' has been synced to $workspace_path."
}

# Source the function
venvsync "$1"
