# configctl Core Belief

Status: living manifesto
Owner repo: `public-dotfiles`
Related design: `docs/configctl-design.md`

`configctl` exists to make machine configuration boring, legible, and
auditable. It is the deterministic control plane for repo-backed configuration,
not the place where judgment, taste, or private context lives.

## Beliefs

1. One command surface beats a pile of scripts.

   Humans and agents should not need to remember which shell script, Taskfile
   block, or historical helper owns a surface. The answer should be a
   `configctl` domain command with typed output and predictable failure modes.

2. Repos are the source of truth.

   Live `$HOME` state is an applied view. Durable intent belongs in
   `public-dotfiles`, `private-config`, and their explicit manifests and
   ledgers. When live state disagrees with repo state, the tool should report
   the disagreement in names and paths a maintainer can inspect.

3. Public code, private data.

   The implementation belongs in the public repo so it can bootstrap without a
   private checkout. Private behavior comes from private manifests, overlays,
   and invocation context. No private-only Go path should be required.

4. Inspection is not mutation.

   `status`, `verify`, `audit`, `validate`, `resolve`, and `export` should be
   safe to run repeatedly. They may observe drift, but they must not fix it
   implicitly.

5. Mutation needs an audit trail.

   Apply-capable commands should name what they touch, support dry-run where
   practical, create backups when replacing live state, and write redacted
   operation reports for later review or release capture.

6. Verification is a contract, not a vibe check.

   `verify` should collect deterministic failures, use stable ordered checks,
   and separate fast required checks from slower full-profile checks. Optional
   disks, GUI state, and network freshness should not leak into the default
   gate.

7. Secrets have shape, never contents.

   Auth and account-local surfaces may be checked for presence, mode, owner,
   parseability, and snapshot status. They must never print tokens, headers,
   credentials, provider secrets, or raw auth payloads in human or JSON output.

8. Domains describe surfaces, not mechanisms.

   `home`, `app`, `agent`, `workspace`, `package`, and `release` are stable
   operator vocabulary. `install`, `doctor`, `symlinks`, and `ownership` are
   implementation history, compatibility aliases, or review language.

9. Taskfiles compose; they do not decide.

   Taskfiles may remain as ergonomic entrypoints, but policy and behavior
   belong in typed configctl domains. Shell should be limited to invoking real
   external tools that have no better local API.

10. Release is scoped by declaration.

    `release capture` exists for explicit paths and compatible operation
    reports. It is not general Git porcelain. Broad staging, history rewriting,
    force pushing, and cleanup-by-release are outside the tool's identity.

11. The tool should refuse to become a second agent brain.

    `configctl` can expose facts, plans, diagnostics, reports, and safe
    mechanical actions. It should not decide whether a config belongs in public
    or private, invent policy, perform account login, or route human judgment.

## Coda

The best version of `configctl` is small enough to trust, typed enough to test,
and explicit enough that a future agent can run it without guessing what it
will change.
