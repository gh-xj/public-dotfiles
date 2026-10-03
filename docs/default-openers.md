# Default File Openers

The public source of truth is `config/macos/default-openers.duti`:
`.md` and `.markdown` use Typora, and PDF uses macOS Preview. The policy contains
only bundle IDs and extensions, so it works across usernames and application
install locations. Other file types retain their current macOS defaults.

[duti](https://github.com/moretension/duti/blob/master/duti.1) applies these
preferences through LaunchServices. Do not copy the live LaunchServices plist
or its registration database into the repo: those contain machine/app state.

The Brewfile supplies `duti`; Home Manager applies the immutable policy during
activation when the Homebrew binary is present. On a new Mac, run `task apps`
and then `task apply`. Run as the logged-in user, without sudo. Query current
state directly with `duti -x md` or `duti -x pdf`.

Typora's license, purchase account and activation state remain private and
app-owned. They are not part of the public policy or the bootstrap.
