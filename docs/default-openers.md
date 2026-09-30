# Default File Openers

The public source of truth is `config/macos/default-openers.duti`:
`.md` and `.markdown` use Typora, and PDF uses macOS Preview. The policy contains
only bundle IDs and extensions, so it works across usernames and application
install locations. Other file types retain their current macOS defaults.

[duti](https://github.com/moretension/duti/blob/master/duti.1) applies these
preferences through LaunchServices. Do not copy the live LaunchServices plist
or its registration database into the repo: those contain machine/app state.

```sh
task openers:list    # current defaults for common extensions; marks managed rows
task openers:plan    # managed preferences and drift, read-only
task openers:apply   # require installed apps, apply, then query actual defaults
task openers:check   # nonzero on missing apps or drift
```

Home Manager supplies `duti`, the `default-openers` command and the immutable
policy. Each activation reapplies preferences for installed apps and reports
missing apps without blocking the rest of a fresh user profile. Run as the
logged-in user, without sudo. Typora is in the public Homebrew cask ledger;
Preview ships with macOS. `task apply` installs the app ledger during its
Darwin phase and reapplies openers strictly afterwards. A direct user-only
Home Manager switch does not install Typora; install the app ledger or Typora
first, then run `default-openers apply`.

Typora's license, purchase account and activation state remain private and
app-owned. They are not part of the public policy or the bootstrap.

`task check` validates the packaged policy without changing live defaults or
requiring GUI apps to be installed. Use `task openers:check` for live evidence.
Installing another app can change associations later; repeat the live check
and apply when needed. This is convergence on activation, not a background
service that continuously enforces defaults.

To adopt another preference, add its bundle ID and extension to the policy
and declare any required third-party app in the Homebrew ledger. Use narrow
types: assigning a broad text type can also affect code or unrelated formats.
Uncommon Markdown aliases remain unmanaged: on some Macs their dynamic UTI
fails duti's extension setter, so validate a new extension before adopting it.
Browser and mail URL schemes should be reviewed separately from file types.
Per-file Finder overrides can also differ from the extension default.
