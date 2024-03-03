#!/bin/bash

# Path to the original .env file
ENV_FILE=".env"

# Path to the new file to write the updated content
NEW_ENV_FILE=".env.docker"

# Check if the .env file exists
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: .env file not found at $ENV_FILE"
    exit 1
fi

# Check if the new env file already exists to prevent accidental overwriting
if [[ -f "$NEW_ENV_FILE" ]]; then
    echo "Error: New env file already exists at $NEW_ENV_FILE"
    exit 1
fi

# Load environment variables from the .env file
set -a
source "$ENV_FILE"
set +a

# Remove any existing content in NEW_ENV_FILE (to start fresh)
> "$NEW_ENV_FILE"

# Read each line from the .env file
while IFS= read -r line || [[ -n "$line" ]]; do
    # Replace templated strings with their corresponding environment variable values
    while [[ "$line" =~ \{\{([A-Z_]+)\}\} ]]; do
        var=${BASH_REMATCH[1]}
        value=${!var}
        line=${line//\{\{$var\}\}/$value}
    done

    # Write the updated line to the new file
    echo "$line" >> "$NEW_ENV_FILE"
done < "$ENV_FILE"

echo "Substitution complete. New file created at: $NEW_ENV_FILE"
