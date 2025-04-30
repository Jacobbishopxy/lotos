#!/usr/bin/env bash
# author:	Jacob Xie
# date:	2025/04/30 17:55:43 Wednesday
# brief:	File operations with random sleep and timeout

# Check if all parameters are provided
if [ $# -lt 3 ]; then
    echo "Usage: $0 <file_path> <max_sleep_seconds> <timeout_seconds>"
    echo "Example: $0 /path/to/file 5 30"
    exit 1
fi

FILE_PATH="$1"
MAX_SLEEP="$2"
TIMEOUT="$3"

# Validate numeric inputs
if ! [[ "$MAX_SLEEP" =~ ^[0-9]+$ ]] || ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
    echo "Error: Sleep and timeout values must be positive integers"
    exit 1
fi

# Check if file exists, create if it doesn't
if [ ! -f "$FILE_PATH" ]; then
    touch "$FILE_PATH" || {
        echo "Error: Cannot create file"
        exit 1
    }
fi

# Function to get current datetime
get_datetime() {
    date "+%Y-%m-%d %H:%M:%S"
}

# Random sleep between 1-max_sleep seconds
random_sleep() {
    sleep $(( ( RANDOM % MAX_SLEEP ) + 1 ))
}

# Export functions to make them available in subshell
export -f get_datetime
export -f random_sleep

# Main operation with timeout
timeout $TIMEOUT bash -c '
    FILE_PATH=$1
    MAX_SLEEP=$2
    while true; do
        echo "[$(get_datetime)] Processing file: $FILE_PATH"
        echo "$(get_datetime)" >> "$FILE_PATH"
        random_sleep
    done
' -- "$FILE_PATH" "$MAX_SLEEP" || echo "Operation timed out after $TIMEOUT seconds"

