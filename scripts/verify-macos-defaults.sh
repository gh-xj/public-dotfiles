#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "macOS defaults verification skipped on non-Darwin host"
  exit 0
fi

read_default() {
  defaults read "$1" "$2" 2>/dev/null || printf '<unset>'
}

extract_plist_raw() {
  local domain="$1"
  local path="$2"
  defaults export "$domain" - 2>/dev/null | plutil -extract "$path" raw -o - - 2>/dev/null || printf '<unset>'
}

assert_default() {
  local domain="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(read_default "$domain" "$key")"
  if [ "$actual" != "$expected" ]; then
    printf 'macOS default mismatch: %s %s expected %s got %s\n' "$domain" "$key" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_plist_raw() {
  local domain="$1"
  local path="$2"
  local expected="$3"
  local actual
  actual="$(extract_plist_raw "$domain" "$path")"
  if [ "$actual" != "$expected" ]; then
    printf 'macOS plist mismatch: %s %s expected %s got %s\n' "$domain" "$path" "$expected" "$actual" >&2
    exit 1
  fi
}

extract_symbolic_hotkey() {
  local path="$1"
  defaults export com.apple.symbolichotkeys - 2>/dev/null | plutil -extract "$path" raw -o - -
}

assert_hotkey() {
  local id="$1"
  local expected="$2"
  local actual
  actual="$(extract_symbolic_hotkey "AppleSymbolicHotKeys.$id.enabled")"
  if [ "$actual" != "$expected" ]; then
    printf 'symbolic hotkey %s enabled expected %s got %s\n' "$id" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_hotkey_param() {
  local id="$1"
  local index="$2"
  local expected="$3"
  local actual
  actual="$(extract_symbolic_hotkey "AppleSymbolicHotKeys.$id.value.parameters.$index")"
  if [ "$actual" != "$expected" ]; then
    printf 'symbolic hotkey %s parameter %s expected %s got %s\n' "$id" "$index" "$expected" "$actual" >&2
    exit 1
  fi
}

assert_default NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically 1
assert_plist_raw NSGlobalDomain AppleLanguages.0 en-US
assert_plist_raw NSGlobalDomain AppleLanguages.1 zh-Hans-US
assert_default NSGlobalDomain AppleLocale en_US
assert_default NSGlobalDomain ApplePressAndHoldEnabled 0
assert_default NSGlobalDomain AppleShowAllExtensions 1
assert_default NSGlobalDomain InitialKeyRepeat 10
assert_default NSGlobalDomain KeyRepeat 1
assert_default NSGlobalDomain NSAutomaticCapitalizationEnabled 1
assert_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled 1
assert_default NSGlobalDomain com.apple.keyboard.fnState 1
assert_default NSGlobalDomain com.apple.trackpad.forceClick 1
assert_default NSGlobalDomain com.apple.trackpad.scaling 3
assert_default .GlobalPreferences com.apple.mouse.scaling 3

assert_default com.apple.dock autohide 1
assert_default com.apple.dock autohide-delay 0
assert_default com.apple.dock autohide-time-modifier 0.5
assert_default com.apple.dock expose-group-apps 1
assert_default com.apple.dock mru-spaces 1
assert_default com.apple.dock show-recents 0
assert_default com.apple.dock tilesize 71

assert_default com.apple.finder AppleShowAllExtensions 1
assert_default com.apple.finder FXPreferredViewStyle clmv
assert_default com.apple.finder ShowPathbar 1

assert_default com.apple.AppleMultitouchMouse MouseButtonMode TwoButton
assert_default com.apple.driver.AppleBluetoothMultitouch.mouse MouseButtonMode TwoButton

assert_default com.apple.AppleMultitouchTrackpad ActuateDetents 1
assert_default com.apple.AppleMultitouchTrackpad Clicking 1
assert_default com.apple.AppleMultitouchTrackpad FirstClickThreshold 0
assert_default com.apple.AppleMultitouchTrackpad SecondClickThreshold 0
assert_default com.apple.AppleMultitouchTrackpad TrackpadRightClick 1
assert_default com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag 1
assert_default com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture 0
assert_default com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture 0
assert_default com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking 1
assert_default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerDrag 1
assert_default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerHorizSwipeGesture 0
assert_default com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture 0

assert_plist_raw com.apple.HIToolbox AppleCurrentKeyboardLayoutInputSourceID com.apple.keylayout.US
assert_plist_raw com.apple.HIToolbox "AppleEnabledInputSources.0.KeyboardLayout Name" U.S.
assert_plist_raw com.apple.HIToolbox "AppleEnabledInputSources.2.Bundle ID" com.apple.inputmethod.SCIM
assert_plist_raw com.apple.HIToolbox "AppleEnabledInputSources.3.Input Mode" com.apple.inputmethod.SCIM.Shuangpin
assert_plist_raw com.apple.HIToolbox "AppleSelectedInputSources.0.KeyboardLayout Name" U.S.

for id in 15 16 17 18 19 20 21 22 23 24 25 26 28 29 30 31 52 64 65 164 184; do
  assert_hotkey "$id" false
done

for id in 60 61 79 80 81 82 118 119 120 121 122; do
  assert_hotkey "$id" true
done

assert_hotkey_param 60 2 393216
assert_hotkey_param 61 2 786432
assert_hotkey_param 79 1 123
assert_hotkey_param 81 1 124
assert_hotkey_param 118 0 49
assert_hotkey_param 122 0 53

echo "macOS defaults baseline verified"
