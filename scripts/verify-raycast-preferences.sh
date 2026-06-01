#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Raycast preferences verification skipped on non-Darwin host"
  exit 0
fi

extract_pref() {
  local key="$1"
  defaults export com.raycast.macos - 2>/dev/null | plutil -extract "$key" raw -o - - 2>/dev/null || printf '<unset>'
}

assert_pref() {
  local key="$1"
  local expected="$2"
  local actual

  actual="$(extract_pref "$key")"
  if [ "$actual" != "$expected" ]; then
    printf 'Raycast preference mismatch: %s expected %s got %s\n' "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_pref raycastGlobalHotkey Command-49
assert_pref raycastPreferredWindowMode compact
assert_pref raycastShouldFollowSystemAppearance true
assert_pref raycastCurrentThemeId bundled-raycast-dark
assert_pref raycastCurrentThemeIdDarkAppearance bundled-raycast-dark
assert_pref raycastCurrentThemeIdLightAppearance bundled-raycast-light
assert_pref navigationCommandStyleIdentifierKey vim
assert_pref showFavoritesInCompactMode true
assert_pref commandsPreferencesShowOnlyCustomized true
assert_pref commandsPreferencesExpandedItemIds.0 builtin_package_scriptCommands
assert_pref commandsPreferencesExpandedItemIds.1 builtin_package_windowManagement
assert_pref commandsPreferencesExpandedItemIds.2 builtin_package_default
assert_pref commandsPreferencesExpandedItemIds.3 applications
assert_pref rootSearchSensitivity medium
assert_pref popToRootTimeout 90
assert_pref raycastWindowEscapeKeyBehavior 1
assert_pref quicklinks_enableAutoFillLink false
assert_pref quicklinks_enableQuickSearch false
assert_pref useHyperKeyIcon true
assert_pref showGettingStartedLink false

echo "Raycast preference baseline verified"
