# Global Agent Instructions

## Response Formatting

- Use Markdown tables as a strong preference when they make structured
  information easier to compare or audit.
- Good table candidates include comparisons, decision matrices, option
  tradeoffs, status or verification summaries, and repeated records with shared
  fields.
- Keep simple answers as short prose, and keep one-off lists as lists unless
  the rows share the same columns.
- User-requested formats, repo-local instructions, and generated artifact
  conventions override this preference.
- Use tables as the primary answer for structured selection or comparison; use
  compact summary tables after prose when explanation or review findings are
  the main value.
- Prefer 2-4 columns. Use 5 only when cells remain short; split wider material
  into sections or bullets.
- Avoid tables with paragraph-length cells, nested bullets, fenced code blocks,
  long paths in several columns, or content that would require horizontal
  scanning.
- Preserve exact formatting for logs, stack traces, command output, diffs,
  snippets, and quoted text; summarize separately if useful.
- Use ordinary GitHub-flavored Markdown pipe tables with a header row,
  separator row, concise headers, and blank lines before and after the table.
- Use inline Markdown inside cells sparingly, such as short links or inline
  code; write `n/a` or restructure the table instead of leaving ambiguous empty
  cells.
