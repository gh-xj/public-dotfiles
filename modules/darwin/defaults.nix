{ config, lib, ... }:

let
  cfg = config.xj.publicDotfiles.darwin;
  homeDir = config.users.users.${config.system.primaryUser}.home;
  usInputSource = {
    InputSourceKind = "Keyboard Layout";
    "KeyboardLayout ID" = 0;
    "KeyboardLayout Name" = "U.S.";
  };
  scimInputSource = {
    "Bundle ID" = "com.apple.inputmethod.SCIM";
    InputSourceKind = "Keyboard Input Method";
  };
  shuangpinInputSource = {
    "Bundle ID" = "com.apple.inputmethod.SCIM";
    "Input Mode" = "com.apple.inputmethod.SCIM.Shuangpin";
    InputSourceKind = "Input Mode";
  };
in
{
  config = lib.mkIf cfg.enable {
    system.defaults = {
      ".GlobalPreferences"."com.apple.mouse.scaling" = 3.0;

      NSGlobalDomain = {
        AppleInterfaceStyleSwitchesAutomatically = true;
        ApplePressAndHoldEnabled = false;
        AppleShowAllExtensions = true;
        InitialKeyRepeat = 10;
        KeyRepeat = 1;
        NSAutomaticCapitalizationEnabled = true;
        NSAutomaticPeriodSubstitutionEnabled = true;
        "com.apple.keyboard.fnState" = true;
        "com.apple.trackpad.forceClick" = true;
        "com.apple.trackpad.scaling" = 3.0;
      };

      dock = {
        autohide = true;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.5;
        expose-group-apps = true;
        mru-spaces = true;
        persistent-apps = [
          { app = "/Applications/Google Chrome.app"; }
          { app = "/Applications/Ghostty.app"; }
        ];
        persistent-others = [
          { folder = "${homeDir}/Downloads"; }
        ];
        show-recents = false;
        tilesize = 71;
      };

      finder = {
        AppleShowAllExtensions = true;
        FXPreferredViewStyle = "clmv";
        ShowPathbar = true;
      };

      magicmouse = {
        MouseButtonMode = "TwoButton";
      };

      trackpad = {
        ActuateDetents = true;
        Clicking = true;
        DragLock = false;
        Dragging = false;
        FirstClickThreshold = 0;
        ForceSuppressed = false;
        SecondClickThreshold = 0;
        TrackpadCornerSecondaryClick = 0;
        TrackpadFourFingerHorizSwipeGesture = 2;
        TrackpadFourFingerPinchGesture = 2;
        TrackpadFourFingerVertSwipeGesture = 2;
        TrackpadMomentumScroll = true;
        TrackpadPinch = true;
        TrackpadRightClick = true;
        TrackpadRotate = true;
        TrackpadThreeFingerDrag = true;
        TrackpadThreeFingerHorizSwipeGesture = 0;
        TrackpadThreeFingerTapGesture = 0;
        TrackpadThreeFingerVertSwipeGesture = 0;
        TrackpadTwoFingerDoubleTapGesture = true;
        TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
      };

      CustomUserPreferences = {
        NSGlobalDomain = {
          AppleLanguages = [
            "en-US"
            "zh-Hans-US"
          ];
          AppleLocale = "en_US";
          "com.apple.mouse.tapBehavior" = 1;
          "com.apple.trackpad.scrolling" = true;
        };

        "com.apple.driver.AppleBluetoothMultitouch.mouse".MouseButtonMode = "TwoButton";

        "com.apple.HIToolbox" = {
          AppleCurrentKeyboardLayoutInputSourceID = "com.apple.keylayout.US";
          AppleEnabledInputSources = [
            usInputSource
            {
              "Bundle ID" = "com.apple.CharacterPaletteIM";
              InputSourceKind = "Non Keyboard Input Method";
            }
            scimInputSource
            shuangpinInputSource
          ];
          AppleInputSourceHistory = [
            usInputSource
            shuangpinInputSource
          ];
          AppleSelectedInputSources = [
            usInputSource
          ];
        };

        "com.raycast.macos" = {
          commandsPreferencesExpandedItemIds = [
            "builtin_package_scriptCommands"
            "builtin_package_windowManagement"
            "builtin_package_default"
            "applications"
          ];
          commandsPreferencesShowOnlyCustomized = true;
          navigationCommandStyleIdentifierKey = "vim";
          popToRootTimeout = 90;
          quicklinks_enableAutoFillLink = false;
          quicklinks_enableQuickSearch = false;
          raycastCurrentThemeId = "bundled-raycast-dark";
          raycastCurrentThemeIdDarkAppearance = "bundled-raycast-dark";
          raycastCurrentThemeIdLightAppearance = "bundled-raycast-light";
          raycastGlobalHotkey = "Command-49";
          raycastPreferredWindowMode = "compact";
          raycastShouldFollowSystemAppearance = true;
          raycastWindowEscapeKeyBehavior = 1;
          rootSearchSensitivity = "medium";
          showFavoritesInCompactMode = true;
          showGettingStartedLink = false;
          useHyperKeyIcon = true;
        };

        "com.apple.symbolichotkeys" = {
          AppleSymbolicHotKeys = {
            "15".enabled = false;
            "16".enabled = false;
            "17".enabled = false;
            "18".enabled = false;
            "19".enabled = false;
            "20".enabled = false;
            "21".enabled = false;
            "22".enabled = false;
            "23".enabled = false;
            "24".enabled = false;
            "25".enabled = false;
            "26".enabled = false;
            "28" = {
              enabled = false;
              value = {
                parameters = [ 51 20 1179648 ];
                type = "standard";
              };
            };
            "29" = {
              enabled = false;
              value = {
                parameters = [ 51 20 1441792 ];
                type = "standard";
              };
            };
            "30" = {
              enabled = false;
              value = {
                parameters = [ 52 21 1179648 ];
                type = "standard";
              };
            };
            "31" = {
              enabled = false;
              value = {
                parameters = [ 52 21 1441792 ];
                type = "standard";
              };
            };
            "52" = {
              enabled = false;
              value = {
                parameters = [ 100 2 1572864 ];
                type = "standard";
              };
            };
            "60" = {
              enabled = true;
              value = {
                parameters = [ 32 49 393216 ];
                type = "standard";
              };
            };
            "61" = {
              enabled = true;
              value = {
                parameters = [ 32 49 786432 ];
                type = "standard";
              };
            };
            "64" = {
              enabled = false;
              value = {
                parameters = [ 32 49 524288 ];
                type = "standard";
              };
            };
            "65" = {
              enabled = false;
              value = {
                parameters = [ 32 49 1572864 ];
                type = "standard";
              };
            };
            "79" = {
              enabled = true;
              value = {
                parameters = [ 65535 123 8650752 ];
                type = "standard";
              };
            };
            "80" = {
              enabled = true;
              value = {
                parameters = [ 65535 123 8781824 ];
                type = "standard";
              };
            };
            "81" = {
              enabled = true;
              value = {
                parameters = [ 65535 124 8650752 ];
                type = "standard";
              };
            };
            "82" = {
              enabled = true;
              value = {
                parameters = [ 65535 124 8781824 ];
                type = "standard";
              };
            };
            "118" = {
              enabled = true;
              value = {
                parameters = [ 49 18 393216 ];
                type = "standard";
              };
            };
            "119" = {
              enabled = true;
              value = {
                parameters = [ 50 19 393216 ];
                type = "standard";
              };
            };
            "120" = {
              enabled = true;
              value = {
                parameters = [ 51 20 393216 ];
                type = "standard";
              };
            };
            "121" = {
              enabled = true;
              value = {
                parameters = [ 52 21 393216 ];
                type = "standard";
              };
            };
            "122" = {
              enabled = true;
              value = {
                parameters = [ 53 23 393216 ];
                type = "standard";
              };
            };
            "164" = {
              enabled = false;
              value = {
                parameters = [ 65535 65535 0 ];
                type = "standard";
              };
            };
            "184" = {
              enabled = false;
              value = {
                parameters = [ 53 23 1179648 ];
                type = "standard";
              };
            };
          };
        };
      };
    };
  };
}
