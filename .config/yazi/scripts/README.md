# Yazi Markdown Preview Optimization

This directory contains scripts to optimize markdown preview performance in Yazi by limiting the number of lines processed.

## Scripts

### `glow-preview.sh`
Simple optimized markdown preview with a fixed 200-line limit.

**Features:**
- Limits preview to first 200 lines for better performance
- Shows notification when file is truncated
- Maintains glow's dark theme styling
- Fast loading for large markdown files

### `glow-preview-configurable.sh`
Advanced configurable markdown preview with environment variable support.

**Environment Variables:**
- `YAZI_MD_MAX_LINES` - Maximum lines to preview (default: 200, set to 0 for no limit)
- `YAZI_MD_STYLE` - Glow theme style (default: "dark")
- `YAZI_MD_SHOW_INFO` - Show truncation info (default: "true")

**Examples:**
```bash
# Set custom line limit
export YAZI_MD_MAX_LINES=500

# Use light theme
export YAZI_MD_STYLE=light

# Disable truncation info
export YAZI_MD_SHOW_INFO=false

# Disable line limit entirely
export YAZI_MD_MAX_LINES=0
```

## Configuration

In your `yazi.toml`, choose one of these markdown preview options:

```toml
# 1. Optimized with 200-line limit (recommended)
{ name = "*.md", run = 'piper -- ~/.config/yazi/scripts/glow-preview.sh "$1" "$w"' },

# 2. Configurable with environment variables
{ name = "*.md", run = 'piper -- ~/.config/yazi/scripts/glow-preview-configurable.sh "$1" "$w"' },

# 3. Original unlimited preview (may be slow for large files)
{ name = "*.md", run = 'piper -- CLICOLOR_FORCE=1 glow -w=$w -s=dark "$1"' },
```

## Performance Benefits

- **Faster loading**: Large markdown files preview instantly
- **Reduced memory usage**: Only processes necessary content
- **Better responsiveness**: Yazi remains responsive when browsing directories with large docs
- **Visual feedback**: Shows when content is truncated

## Customization

You can modify the scripts to:
- Change the default line limit
- Adjust the glow styling options
- Add support for other markdown processors (like `bat`, `mdcat`, etc.)
- Include file statistics or metadata in the preview

## Troubleshooting

If previews aren't working:

1. Ensure scripts are executable:
   ```bash
   chmod +x ~/.config/yazi/scripts/*.sh
   ```

2. Check that `glow` is installed:
   ```bash
   which glow
   ```

3. Test the script directly:
   ```bash
   ~/.config/yazi/scripts/glow-preview.sh /path/to/file.md 80
   ```

4. Verify the path in your `yazi.toml` is correct and uses absolute paths or proper shell expansion.
