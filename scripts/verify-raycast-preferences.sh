#!/usr/bin/env bash
set -euo pipefail

mode="verify"
domain="com.raycast.macos"
expanded_item_ids=(
  "builtin_package_scriptCommands"
  "builtin_package_windowManagement"
  "builtin_package_default"
  "applications"
)

usage() {
  cat <<'EOF'
Usage: verify-raycast-preferences.sh [--verify|--apply]

Verify or apply the public-safe Raycast defaults baseline.
EOF
}

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Raycast preferences verification skipped on non-Darwin host"
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --verify)
      mode="verify"
      ;;
    --apply)
      mode="apply"
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      printf 'raycast-preferences: unknown option: %s\n' "$1" >&2
      exit 1
      ;;
  esac
  shift
done

extract_pref() {
  local key="$1"
  defaults export "$domain" - 2>/dev/null | plutil -extract "$key" raw -o - - 2>/dev/null || printf '<unset>'
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

verify_pref() {
  local key="$1"
  local _type="$2"
  local value="$3"

  assert_pref "$key" "$value"
}

write_pref() {
  local key="$1"
  local type="$2"
  local value="$3"

  case "$type" in
    bool)
      defaults write "$domain" "$key" -bool "$value"
      ;;
    int)
      defaults write "$domain" "$key" -int "$value"
      ;;
    string)
      defaults write "$domain" "$key" -string "$value"
      ;;
    *)
      printf 'raycast-preferences: unsupported type for %s: %s\n' "$key" "$type" >&2
      exit 1
      ;;
  esac
}

visit_scalar_prefs() {
  local callback="$1"

  "$callback" raycastGlobalHotkey string Command-49
  "$callback" raycastPreferredWindowMode string compact
  "$callback" raycastShouldFollowSystemAppearance bool true
  "$callback" raycastCurrentThemeId string bundled-raycast-dark
  "$callback" raycastCurrentThemeIdDarkAppearance string bundled-raycast-dark
  "$callback" raycastCurrentThemeIdLightAppearance string bundled-raycast-light
  "$callback" navigationCommandStyleIdentifierKey string vim
  "$callback" showFavoritesInCompactMode bool true
  "$callback" commandsPreferencesShowOnlyCustomized bool true
  "$callback" rootSearchSensitivity string medium
  "$callback" popToRootTimeout int 90
  "$callback" raycastWindowEscapeKeyBehavior int 1
  "$callback" quicklinks_enableAutoFillLink bool false
  "$callback" quicklinks_enableQuickSearch bool false
  "$callback" useHyperKeyIcon bool true
  "$callback" showGettingStartedLink bool false
}

verify_array_prefs() {
  local idx

  for idx in "${!expanded_item_ids[@]}"; do
    assert_pref "commandsPreferencesExpandedItemIds.$idx" "${expanded_item_ids[$idx]}"
  done
}

apply_array_prefs() {
  defaults write "$domain" commandsPreferencesExpandedItemIds -array "${expanded_item_ids[@]}"
}

case "$mode" in
  verify)
    visit_scalar_prefs verify_pref
    verify_array_prefs
    echo "Raycast preference baseline verified"
    ;;
  apply)
    visit_scalar_prefs write_pref
    apply_array_prefs
    killall cfprefsd >/dev/null 2>&1 || true
    echo "Raycast preference baseline applied"
    ;;
esac
