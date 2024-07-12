#!/bin/bash

# Set configuration file paths
CONFIG_FILE="$(dirname "$0")/locations.cfg"
BACKUP_DIR="$(dirname "$0")/backups"
LOG_FILE="$(dirname "$0")/backup.log"
CHECKSUM_FILE="$(dirname "$0")/checksums.log"

# Function to list locations from the configuration file
function list_locations() {
  local i=1
  while IFS= read -r line; do
    echo "$i. $line"
    i=$((i + 1))
  done < "$CONFIG_FILE"
}

# Function to calculate SHA-256 checksum of a file
function calculate_checksum() {
  sha256sum "$1" | awk '{print $1}'
}

# Function to perform backup
function backup() {
  local line_num=$1
  local i=1
  while IFS= read -r line; do
    if [ -z "$line_num" ] || [ "$i" -eq "$line_num" ]; then
      # Extract user, host, and path from the configuration line
      local user_host_path=(${line//@/ })
      local host_path=(${user_host_path[1]//:/ })
      local user=${user_host_path[0]}
      local host=${host_path[0]}
      local path=${host_path[1]}
      local target_dir="$BACKUP_DIR/$(echo $host | tr '.' '_')"

      # Create target directory for backups
      mkdir -p "$target_dir"
      touch "$CHECKSUM_FILE"
      echo "Starting backup from $line..."
      echo "======Starting backup from $line...======" >> "$LOG_FILE"

      # Dry-run rsync to verify checksums
      rsync -avz -e "ssh -i ~/.ssh/id_rsa" --dry-run "$user@$host:$path/" "$target_dir" --checksum --out-format="%n" | while read -r file; do
        local remote_file="$path/$file"
        local local_file="$target_dir/$file"
        local original_checksum
        local new_checksum

        if [ -f "$local_file" ]; then
          # Calculate original and new checksums
          original_checksum=$(calculate_checksum "$local_file")
          new_checksum=$(ssh "$user@$host" "sha256sum '$remote_file'" | awk '{print $1}')

          if [ "$original_checksum" != "$new_checksum" ]; then
            # Move the original file to .phantom if checksums differ
            cp "$local_file" "${local_file}.phantom"
            echo "$local_file flagged as .phantom" >> "$LOG_FILE"
            echo "Original: $original_checksum, New: $new_checksum" >> "$LOG_FILE"
          fi
        fi
      done

      # Perform actual rsync backup
      rsync -avz -e "ssh" "$user@$host:$path/" "$target_dir" --checksum >> "$LOG_FILE" 2>&1
      rsync_exit_status=$?

      if [ $rsync_exit_status -eq 0 ]; then
        # Update checksums for successfully backed up files
        echo "Backup from $line completed successfully."
        echo "Backup from $line completed successfully." >> "$LOG_FILE"
        find "$target_dir" -type f ! -name "*.phantom" | while read -r file; do
          local new_checksum
          new_checksum=$(calculate_checksum "$file")
          echo "$new_checksum $file" >> "$CHECKSUM_FILE"
        done
      else
        echo "Backup from $line failed. Rsync exit status: $rsync_exit_status" >> "$LOG_FILE"
      fi
    fi
    i=$((i + 1))
  done < "$CONFIG_FILE"
}

function restore() {
  local backup_num=$1
  local line_num=$2
  local integrity_check=$3
  local i=1

  # Print current directory and list contents
  pwd
  ls -l "$BACKUP_DIR"

  while IFS= read -r line; do
    if [ -z "$line_num" ] || [ "$i" -eq "$line_num" ]; then
      # Get user, host, and path from the configuration line
      local user_host_path=(${line//@/ })
      local host_path=(${user_host_path[1]//:/ })
      local user=${user_host_path[0]}
      local host=${host_path[0]}
      local path=${host_path[1]}
      local source_dir="$BACKUP_DIR/$(echo $host | tr '.' '_')"

      echo "Starting restore to $line from backup $backup_num..."
      echo "======Starting restore to $line from backup $backup_num...======" >> "$LOG_FILE"
      echo "Source directory: $source_dir" >> "$LOG_FILE"

      if [ -d "$source_dir" ]; then
        echo "Backup directory exists. Proceeding with restore." >> "$LOG_FILE"

        # Perform rsync restore
        rsync -avz "$source_dir/" "$user@$host:$path" >> "$LOG_FILE" 2>&1
        rsync_exit_status=$?

        if [ $rsync_exit_status -eq 0 ]; then
          echo "Restore to $line from backup $backup_num completed successfully."
          echo "Restore to $line from backup $backup_num completed successfully." >> "$LOG_FILE"

          if [ "$integrity_check" == "-I" ]; then
            echo "Executing integrity_check"
            # Revert altered files (if checksums match)
            find "$source_dir" -type f -name "*.phantom" | while read -r file; do
              local original_file=${file%.phantom}
              local original_checksum
              original_checksum=$(grep "$original_file" "$CHECKSUM_FILE" | awk '{print $1}')
              local current_checksum
              current_checksum=$(calculate_checksum "$original_file")

              if [ "$original_checksum" == "$current_checksum" ]; then
                mv "$file" "$original_file"
                echo "Restored $original_file to its original state." >> "$LOG_FILE"
              fi
            done
          fi
        else
          echo "Restore to $line from backup $backup_num failed. Rsync exit status: $rsync_exit_status"
          echo "Restore to $line from backup $backup_num failed. Rsync exit status: $rsync_exit_status" >> "$LOG_FILE"
        fi
      else
        echo "Backup directory $source_dir does not exist." >> "$LOG_FILE"
      fi
    fi
    i=$((i + 1))
  done < "$CONFIG_FILE"
}


## Main
case "$1" in
  -B)
    if [ "$2" == "-L" ] && [ -n "$3" ]; then
      backup "$3"
    else
      backup
    fi
    ;;
  -R)
    if [ -n "$2" ]; then
      if [ "$3" == "-L" ] && [ -n "$4" ]; then
        restore "$2" "$4" "$5"
      else
        restore "$2" "$3"
      fi
    else
      echo "Please specify which backup to restore."
    fi
    ;;
  *)
    list_locations
    ;;
esac
