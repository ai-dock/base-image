#!/bin/false

# Function to set the virtual environment
setvenv() {
    local venv_name=$1

    if [ -z "$venv_name" ]; then
        echo "Usage: source venv-set <venvname>"
        return 1
    fi

    local workspace_path="${WORKSPACE}environments/python/$venv_name"
    local opt_path="/opt/environments/python/$venv_name"
    local venv_path=""

    if [ -d "$workspace_path" ]; then
        venv_path="$workspace_path"
    elif [ -d "$opt_path" ]; then
        venv_path="$opt_path"
    else
        echo "Error: Neither $workspace_path nor $opt_path exists."
        return 1
    fi

    export ${venv_name^^}_VENV="$venv_path"
    export ${venv_name^^}_VENV_PYTHON="$venv_path/bin/python"
    export ${venv_name^^}_VENV_PIP="$venv_path/bin/pip"

    echo "Virtual environment '$venv_name' set at $venv_path."
}

# Source the function
setvenv "$1"
