#!/bin/bash

# Path to the Python script
script_path="/home/$USER/ranphoto.py"

# Check if the Python script exists
if [ ! -f "$script_path" ]; then
    echo "Error: File not found at $script_path"
    exit 1
fi

# Prompt the user for the new maximum value
read -p "Enter the new maximum value for the random number: " new_max

# Validate if the input is a valid positive integer
if ! [[ "$new_max" =~ ^[0-9]+$ ]] || [ "$new_max" -lt 1 ]; then
    echo "Error: Please enter a valid positive integer."
    exit 1
fi
