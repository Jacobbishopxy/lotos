#!/usr/bin/env bash
# author:	Jacob Xie
# date:	2025/04/30 20:04:29 Wednesday
# brief:	Sleep for specified duration then exit with failure

# Check if parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <sleep_duration>"
    exit 1
fi

# Sleep for specified duration
sleep "$1"

# Exit with failure code
exit 1

