#!/bin/bash

storage_dir="$(readlink -f ${WORKSPACE}/storage)"
image_storage_dir="$(readlink -f /opt/storage)"
source /opt/ai-dock/storage_monitor/etc/mappings.sh
# Link files bundled in the image to $storage_dir
if [[ -d $image_storage_dir && "$(readlink -f $image_storage_dir)" != "$(readlink -f $storage_dir)" ]]; then
    IFS=$'\n'
    for filepath in $(find "$image_storage_dir" -type f -name "[!.]*" ); do
        file_name=$(basename "$filepath")
        dir_name=$(dirname "$filepath")
        ws_file_path=${storage_dir}/$(realpath --relative-to="$image_storage_dir" "$filepath")
        ws_dir_name=$(dirname "$ws_file_path")
        
        mkdir -p "$ws_dir_name"
        ln -sf "$filepath" "$ws_file_path"
    done
else
    printf "Skipping container/workspace storage sync (symlinked)\n"
fi

# Initial pass for existing files
find "$storage_dir" -exec bash /opt/ai-dock/storage_monitor/bin/manage-symlinks.sh "$storage_dir" {} \;

# Delete any broken symlinks caused by containers sharing a volume
for app_directory in "${!storage_map[@]}"; do
    read -ra target_dirs <<< "${storage_map["$app_directory"]}"
    for target_directory in "${target_dirs[@]}"; do
        if [[ -e $target_directory ]]; then
            find "$target_directory" -xtype l -delete
        fi
    done
done

# Inotify loop for future changes in $storage_dir
inotifywait -m -r -e create -e delete -e move --format '%e %w%f' "$storage_dir" |
while read -r changed_item
do
    event_type=$(echo "$changed_item" | awk '{print $1}')
    stored_file=$(echo "$changed_item" | awk '{print $2}')
    # Call the function to create or remove symlinks for the changed item
    bash /opt/ai-dock/storage_monitor/bin/manage-symlinks.sh "$storage_dir" "$stored_file" "$event_type"
done
