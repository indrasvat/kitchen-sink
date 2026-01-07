#!/usr/bin/env bash

# Set the delay for grouping notifications (in seconds)
DELAY=${DELAY:-1}

# Check if a command was provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>"
    echo "\tExample: $0 kubectl get po --watch --no-headers"
    exit 1
fi

# The command to execute
COMMAND="$*"

# Function to play the sound
play_sound() {
    afplay ~/Downloads/chirp.wav
}

# Function to process output and handle timing
process_output() {
    local last_event_time=0
    local current_time
    local event_count=0

    while IFS= read -r line; do
        echo "$line"  # Output the line
        event_count=$((event_count + 1))
        
        # Get the current time in seconds
        current_time=$(date +%s)

        # Check if delay has passed since the last event
        if (( current_time - last_event_time >= DELAY )); then
            # If enough time has passed, play the sound and reset
            # echo "Events: $event_count"
            play_sound
            event_count=0
            last_event_time=$current_time
        fi
    done
}

# Function to handle cleanup on exit
cleanup() {
    echo "Cleaning up..."
    pkill -P $$  # Kill all child processes
    exit 0
}

# Trap to handle Ctrl+C and other termination signals
trap cleanup EXIT INT TERM

# Run the provided command and process its output
if ! eval "$COMMAND" | process_output; then
    echo "Error: Failed to execute the command."
    exit 1
fi
