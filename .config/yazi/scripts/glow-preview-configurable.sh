#!/bin/bash

# Configurable markdown preview script for Yazi
# Supports environment variables for customization

FILE="$1"
WIDTH="$2"

# Configuration via environment variables with sensible defaults
MAX_LINES="${YAZI_MD_MAX_LINES:-200}"
GLOW_STYLE="${YAZI_MD_STYLE:-dark}"
SHOW_LINE_INFO="${YAZI_MD_SHOW_INFO:-true}"

# Check if file exists
if [[ ! -f "$FILE" ]]; then
    echo "File not found: $FILE"
    exit 1
fi

# Get total line count
TOTAL_LINES=$(wc -l < "$FILE")

# Preview the content (limited if necessary)
if [[ $TOTAL_LINES -le $MAX_LINES ]]; then
    # File is small enough, show entire content
    CLICOLOR_FORCE=1 glow -w="${WIDTH:-80}" -s="$GLOW_STYLE" "$FILE"
else
    # File is large, show limited content
    head -n "$MAX_LINES" "$FILE" | CLICOLOR_FORCE=1 glow -w="${WIDTH:-80}" -s="$GLOW_STYLE" -
    
    # Show info about truncation if enabled
    if [[ "$SHOW_LINE_INFO" == "true" ]]; then
        echo ""
        echo "📄 Preview limited to first $MAX_LINES lines for performance"
        echo "   File has $TOTAL_LINES total lines ($(($TOTAL_LINES - $MAX_LINES)) lines hidden)"
        echo "   Set YAZI_MD_MAX_LINES=0 to disable limit"
    fi
fi