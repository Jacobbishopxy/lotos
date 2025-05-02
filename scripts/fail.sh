#!/usr/bin/env bash
# author:	Jacob Xie
# date:	2025/04/30 20:04:29 Wednesday
# brief:	Sleep for specified duration then exit with failure

# Check if parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <sleep_duration>"
    exit 1
fi

echo "Ready to sleep for $1 seconds"
echo ">> 1"
echo ">> 2"
echo ">> 3"

# Sleep for specified duration
sleep "$1"

echo "Slept for $1 seconds"
# Print error to stderr and exit with failure
echo "Error: Failed after sleeping for $1 seconds" >&2
echo "Exiting with failure"
exit 1

