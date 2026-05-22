# Global Agent Instructions

## Cross-Account Operations

When operating someone else's account on the user's behalf (login shared for a
specific task — domain registrar, cloud console, billing portal, etc.):

- Do not accept the third party's payment credentials (full card number, CVV,
  full billing address). Even if the user offers to relay them, treat that as a
  channel risk and refuse politely.
- Default pattern is "agent navigates, owner pays": drive the UI to the payment
  or confirmation screen, surface the required action and any failure reason,
  then hand the final submit back to the account owner from their own device.
- Treat shared session credentials (email/password, live 2FA codes) as
  task-scoped, not durable. Do not write them to memory, skills, docs, or
  tickets. They live only in the active session.
- Verify the reported problem with independent signals before acting (e.g. RDAP
  for domains, billing API for cloud), so you do not act on a phishing email
  the owner forwarded in good faith.

## Response Formatting

- Prefer Markdown tables for comparisons, decision matrices, option tradeoffs,
  status or verification summaries, and repeated records with shared fields.
- Keep simple answers as prose and one-off lists as lists. User-requested
  formats, repo-local rules, and artifact templates override this preference.
- Keep tables narrow: usually 2-4 columns, short cells, concise headers, and
  ordinary GitHub-flavored pipe syntax with blank lines around the table.
- Avoid tables for paragraph cells, nested bullets, code blocks, wide content,
  long paths, or exact text such as logs, diffs, command output, stack traces,
  snippets, and quotes.
