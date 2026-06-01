#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "macOS baseline inspection skipped on non-Darwin host"
  exit 0
fi

section() {
  printf '\n## %s\n' "$1"
}

plist_raw() {
  local domain="$1"
  local key="$2"
  defaults export "$domain" - 2>/dev/null | plutil -extract "$key" raw -o - - 2>/dev/null || printf '<unset>'
}

defaults_raw() {
  local domain="$1"
  local key="$2"
  defaults read "$domain" "$key" 2>/dev/null | tr '\n' ' ' | sed -E 's/[[:space:]]+$//' || printf '<unset>'
}

find_cmd() {
  local name="$1"
  local candidate

  if command -v "$name" >/dev/null 2>&1; then
    command -v "$name"
    return 0
  fi

  for candidate in \
    "/opt/homebrew/bin/$name" \
    "/usr/local/bin/$name"
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

print_default() {
  local label="$1"
  local domain="$2"
  local key="$3"
  printf '%-38s %s\n' "$label" "$(defaults_raw "$domain" "$key")"
}

print_plist_default() {
  local label="$1"
  local domain="$2"
  local key="$3"
  printf '%-38s %s\n' "$label" "$(plist_raw "$domain" "$key")"
}

print_dock_items() {
  local key="$1"
  defaults export com.apple.dock - 2>/dev/null |
    plutil -extract "$key" xml1 -o - - 2>/dev/null |
    plutil -p - 2>/dev/null |
    awk '/file-label|_CFURLString/ { sub(/^[[:space:]]+/, ""); print }' || true
}

print_raycast_extensions() {
  local dir

  for dir in \
    "$HOME/.config/raycast/extensions" \
    "$HOME/Library/Application Support/com.raycast.macos/extensions"
  do
    [ -d "$dir" ] || continue
    find "$dir" -maxdepth 2 -name package.json -print
  done |
    sort -u |
    while IFS= read -r package_json; do
      name="$(plutil -extract name raw -o - "$package_json" 2>/dev/null || basename "$(dirname "$package_json")")"
      title="$(plutil -extract title raw -o - "$package_json" 2>/dev/null || printf '')"
      if [ -n "$title" ] && [ "$title" != "$name" ]; then
        printf '%s\t%s\n' "$name" "$title"
      else
        printf '%s\n' "$name"
      fi
    done |
    sort -u
}

print_script_commands() {
  local dir
  local ledger="$repo_root/config/raycast/script-commands.tsv"
  local script title mode package boundary notes
  local dirs=(
    "$HOME/.config/raycast/scripts"
    "$HOME/.config/xj_public_raycast_scripts"
  )

  if [ -f "$ledger" ]; then
    printf '\ndesired public commands from repo\n'
    while IFS=$'\t' read -r script title mode package boundary notes; do
      case "$script" in
        ""|\#*)
          continue
          ;;
      esac
      printf '  %s - %s\n' "$script" "$title"
    done <"$ledger"
  fi

  if [ "${XJ_PUBLIC_DOTFILES_INSPECT_PRIVATE_RAYCAST:-0}" = "1" ]; then
    dirs+=("$HOME/.config/xj_raycast_scripts")
  fi

  for dir in "${dirs[@]}"; do
    [ -d "$dir" ] || continue
    printf '\n%s\n' "$dir"
    find "$dir" -maxdepth 1 -type f \( -name '*.sh' -o -name '*.py' \) -print |
      sort |
      while IFS= read -r script_file; do
        title="$(sed -n 's/^# @raycast.title //p' "$script_file" | head -1)"
        printf '  %s' "$(basename "$script_file")"
        [ -n "$title" ] && printf ' - %s' "$title"
        printf '\n'
      done
  done

  if [ -d "$HOME/.config/xj_raycast_scripts" ] &&
    [ "${XJ_PUBLIC_DOTFILES_INSPECT_PRIVATE_RAYCAST:-0}" != "1" ]; then
    printf '\nprivate Raycast script directory omitted; set XJ_PUBLIC_DOTFILES_INSPECT_PRIVATE_RAYCAST=1 for local-only triage\n'
  fi
}

print_current_host_input_defaults() {
  local defaults_file="$repo_root/config/macos/current-host-defaults.tsv"
  local domain key type value actual

  [ -f "$defaults_file" ] || return 0
  while IFS=$'\t' read -r domain key type value; do
    case "$domain" in
      ""|\#*)
        continue
        ;;
    esac
    actual="$(defaults -currentHost read "$domain" "$key" 2>/dev/null || printf '<unset>')"
    printf '%-52s %s\n' "$key" "$actual"
  done <"$defaults_file"
}

print_user_input_defaults() {
  local defaults_file="$repo_root/config/macos/input-user-defaults.tsv"
  local domain key type value actual

  [ -f "$defaults_file" ] || return 0
  while IFS=$'\t' read -r domain key type value; do
    case "$domain" in
      ""|\#*)
        continue
        ;;
    esac
    actual="$(defaults read "$domain" "$key" 2>/dev/null || printf '<unset>')"
    printf '%-52s %s\n' "$key" "$actual"
  done <"$defaults_file"
}

live_trackpad_preferences() {
  ioreg -r -c AppleMultitouchDevice -l -w0 2>/dev/null |
    sed -n 's/.*"MultitouchPreferences" = {\(.*\)}.*/\1/p' |
    head -1
}

print_live_trackpad_defaults() {
  local defaults_file="$repo_root/config/macos/live-trackpad-defaults.tsv"
  local prefs key expected actual

  [ -f "$defaults_file" ] || return 0
  prefs="$(live_trackpad_preferences)"
  if [ -z "$prefs" ]; then
    echo "no live AppleMultitouchDevice preferences found"
    return 0
  fi

  while IFS=$'\t' read -r key expected; do
    case "$key" in
      ""|\#*)
        continue
        ;;
    esac
    actual="$(printf '%s\n' "$prefs" | sed -nE "s/.*\"$key\"=([^,}]+).*/\1/p")"
    printf '%-52s %s\n' "$key" "${actual:-<unset>}"
  done <"$defaults_file"
}

section "Display"
system_profiler SPDisplaysDataType | sed -n '/Displays:/,$p' | sed -n '1,140p'
displayplacer_cmd="$(find_cmd displayplacer || true)"
if [ -n "$displayplacer_cmd" ]; then
  printf '\n# displayplacer\n'
  "$displayplacer_cmd" list | sed -n '1,120p'
else
  printf '\n# displayplacer\nnot installed\n'
fi

section "Global Defaults"
print_plist_default "AppleLanguages[0]" NSGlobalDomain AppleLanguages.0
print_plist_default "AppleLanguages[1]" NSGlobalDomain AppleLanguages.1
print_default "AppleLocale" NSGlobalDomain AppleLocale
print_default "KeyRepeat" NSGlobalDomain KeyRepeat
print_default "InitialKeyRepeat" NSGlobalDomain InitialKeyRepeat
print_default "ApplePressAndHoldEnabled" NSGlobalDomain ApplePressAndHoldEnabled
print_default "mouse scaling" .GlobalPreferences com.apple.mouse.scaling
print_default "trackpad scaling" NSGlobalDomain com.apple.trackpad.scaling
print_default "fn state" NSGlobalDomain com.apple.keyboard.fnState

section "CurrentHost Input Defaults"
print_current_host_input_defaults

section "User Input Defaults"
print_user_input_defaults

section "Live Trackpad Defaults"
print_live_trackpad_defaults

section "Input Sources"
defaults export com.apple.HIToolbox - 2>/dev/null | plutil -p - 2>/dev/null | sed -n '1,220p' || true

section "Dock"
printf 'persistent-apps:\n'
print_dock_items persistent-apps
printf '\npersistent-others:\n'
print_dock_items persistent-others

section "Spaces"
print_plist_default "main display spaces" com.apple.spaces "SpacesDisplayConfiguration.Management Data.Monitors.0.Spaces"

section "Raycast Preferences"
for key in \
  raycastGlobalHotkey \
  raycastPreferredWindowMode \
  raycastShouldFollowSystemAppearance \
  raycastCurrentThemeId \
  raycastCurrentThemeIdDarkAppearance \
  raycastCurrentThemeIdLightAppearance \
  navigationCommandStyleIdentifierKey \
  showFavoritesInCompactMode \
  commandsPreferencesShowOnlyCustomized \
  commandsPreferencesExpandedItemIds.0 \
  commandsPreferencesExpandedItemIds.1 \
  commandsPreferencesExpandedItemIds.2 \
  commandsPreferencesExpandedItemIds.3 \
  rootSearchSensitivity \
  popToRootTimeout \
  raycastWindowEscapeKeyBehavior \
  quicklinks_enableAutoFillLink \
  quicklinks_enableQuickSearch \
  useHyperKeyIcon \
  showGettingStartedLink
do
  print_plist_default "$key" com.raycast.macos "$key"
done

section "Raycast Extensions"
print_raycast_extensions | sed -n '1,220p'

section "Raycast Script Commands"
print_script_commands
