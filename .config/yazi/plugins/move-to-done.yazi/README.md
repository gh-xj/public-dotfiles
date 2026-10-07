# Move to Done

`Ud` moves hovered or selected local items into `Done/` under the current
browsing directory. Existing names are skipped rather than overwritten. The
Done directory itself is skipped, and a symlink or non-directory destination
is refused. Failed moves are reported; filenames are passed as argv, including
spaces and quotes.

This repo-owned plugin uses Yazi filesystem APIs and `mv -n`. It replaces the
retired external helper without changing the keybinding.
