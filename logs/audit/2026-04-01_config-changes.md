# 2026-04-01 Config Changes

- Timestamp: 2026-04-01T22:41:30-0700
  Action: Installed Handy via Homebrew cask
  Files affected: /Applications/Handy.app
  Result: success; `brew install --cask handy` installed Handy 0.8.2
  Notes: Added `cask "handy"` to repo `Brewfile` so this install is reproducible.

- Timestamp: 2026-04-01T22:44:00-0700
  Action: Tracked Handy settings in public dotfiles
  Files affected: Library/Application Support/com.pais.handy/settings_store.json, install.sh
  Result: success; added Handy settings file to repo installer ownership
  Notes: Kept `selected_language` as `auto` for mixed Chinese and English dictation. Excluded `history.db`, `recordings/`, and `models/` as runtime state.

- Timestamp: 2026-04-01T22:47:00-0700
  Action: Set Handy default model for mixed Chinese and English dictation
  Files affected: Library/Application Support/com.pais.handy/settings_store.json
  Result: success; set `selected_model` to `sense-voice-int8`
  Notes: Chosen because Handy upstream defines this model as supporting `zh`, `zh-Hans`, `zh-Hant`, `en`, `yue`, `ja`, and `ko`.
