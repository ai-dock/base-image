#!/bin/bash

storage_dir="$1"
stored_file="$2"
event_type="$3"

absolute_stored_file=$(realpath "$stored_file")
subfolder=$(realpath --relative-to="$storage_dir" "$(dirname "$stored_file")")

# Simplify per-image settings by keeping mappings separate
source /opt/ai-dock/storage_monitor/etc/mappings.sh

# Function to create symlinks for a given file and repository directory
manage_symlinks() {
    for app_directory in "${!storage_map[@]}"; do
        if [[ "$subfolder" == "$app_directory" ]]; then
            read -ra target_dirs <<< "${storage_map["$app_directory"]}"
            for target_directory in "${target_dirs[@]}"; do
                symlink_target="$target_directory/$(basename "$stored_file")"
                symlink_target_dir="$(dirname "$symlink_target")"
                if [[ -e "$stored_file" ]]; then
                    # Create symlinks for existing or newly created files
                    mkdir -p "$symlink_target_dir"
                    ln -sf "$absolute_stored_file" "$symlink_target"
                else
                    # Remove symlink for deleted files
                    rm -f "$symlink_target"
                fi
            done
        fi
    done
}

# Call the function to create or remove symlinks for the stored file
manage_symlinks
