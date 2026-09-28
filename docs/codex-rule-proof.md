# Runtime evidence for destructive-command prefixes

The public rules now cover these explicit argv prefixes:

| Prefix | Decision |
| --- | --- |
| `rm -rf /` (also `/bin/rm`, `/usr/bin/rm`) | forbidden |
| `git push --force` / `git push -f` | prompt |
| `git reset --hard` | prompt |
| `git clean -fd` | prompt |

On Codex CLI 0.158.0, the disposable runtime matrix passed all 20 cases: five
command forms, an allow control and the intended restriction for each, under
both `approval_policy=never` with `danger-full-access` and the explicit bypass
flag. All ten controls created their markers. All ten restricted cases lacked
markers and returned the expected pre-execution policy rejection. With `never`,
a prompt decision rejects execution because approval cannot be surfaced; it
does not silently allow the operation.

## Reproduce

```sh
python3 scripts/probe-codex-rules.py
```

`task check` runs this probe as a regression gate. It uses the real installed
Codex CLI, a fresh config and temporary Git repository per case, and a loopback
Responses fixture server that requests one predetermined shell-tool invocation.
There are no external model requests and no account credentials are required.
The fixture polls asynchronous tool sessions to completion before concluding.

The executables named `rm` and `git` in these probes are inert marker writers,
invoked by absolute path. **No real root deletion, reset, clean or force push is
performed.** Temporary rules add that exact stub path as an alternative to the
canonical command name; the same decision/prefix suffix is exercised by the
runtime. A separate native `execpolicy check` verifies the published rules match
the canonical commands. Positive controls prove that absence of a marker is
not merely a broken executable, tool transport or permission environment.

The command prints the evidence directory. Each case retains its marker (allow
only), rule/config, CLI stdout/stderr and result JSON; `summary.json` records
the CLI version and outcomes. These are disposable local test artifacts, not
public session data. Review and record the result before explicitly removing
them. An inconclusive or changed runtime result fails the gate; do not claim
enforcement from a static classifier alone.

## Limits

These are **prefix rules**, not a command-language firewall or OS sandbox. They
do not cover arbitrary option reordering such as `git push origin main --force`,
all absolute Git executable paths, aliases, scripts that invoke destructive
commands internally, or every equivalent spelling. Do not describe them as
universal protection. Public policy still requires explicit intent, bounded
targets and preservation of other work. Normal pushes and previews are not
blocked by these prefixes. Use interactive approval or a reviewed manual action
when an intended destructive operation is rejected under `never`.

Rules are experimental. See the official
[Codex rules reference](https://learn.chatgpt.com/docs/agent-configuration/rules).
The regression test, rather than the installed version number alone, is the
evidence required after a CLI update. Downstream `codexRules.extraText` is for
private-only commands; do not keep duplicate generic rules in a local patch.
