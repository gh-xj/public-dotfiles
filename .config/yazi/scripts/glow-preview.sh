#!/bin/bash

# Optimized markdown preview script for Yazi
# Limits content to first 200 lines for better performance

FILE="$1"
WIDTH="$2"

# Check if file exists
if [[ ! -f "$FILE" ]]; then
    echo "File not found: $FILE"
    exit 1
fi

# Get the first 200 lines and pipe to glow
head -n 200 "$FILE" | CLICOLOR_FORCE=1 glow -w="${WIDTH:-80}" -s=dark -

# If file has more than 200 lines, show a notice
if [[ $(wc -l < "$FILE") -gt 200 ]]; then
    echo ""
    echo "📄 Preview limited to first 200 lines for performance"
    echo "   File has $(wc -l < "$FILE") total lines"
fi