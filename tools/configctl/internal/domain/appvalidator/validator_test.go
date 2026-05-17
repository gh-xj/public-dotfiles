package appvalidator

import (
	"os"
	"path/filepath"
	"testing"
)

func TestKarabinerTerminalInvariantAllowsChromeScopedTabRewrite(t *testing.T) {
	path := writeKarabinerConfig(t, `{
  "rules": [
    {
      "manipulators": [
        {
          "type": "basic",
          "from": {
            "key_code": "h",
            "modifiers": { "mandatory": ["control"] }
          },
          "to": [
            {
              "key_code": "open_bracket",
              "modifiers": ["command", "shift"]
            }
          ],
          "conditions": [
            {
              "type": "frontmost_application_if",
              "bundle_identifiers": ["^com\\.google\\.Chrome$"]
            }
          ]
        }
      ]
    }
  ]
}`)

	if err := verifyKarabinerTerminalInvariants(path); err != nil {
		t.Fatalf("expected Chrome-scoped rewrite to pass: %v", err)
	}
}

func TestKarabinerTerminalInvariantRejectsGlobalTerminalTabRewrite(t *testing.T) {
	path := writeKarabinerConfig(t, `{
  "rules": [
    {
      "manipulators": [
        {
          "type": "basic",
          "from": {
            "key_code": "l",
            "modifiers": { "mandatory": ["control"] }
          },
          "to": [
            {
              "key_code": "close_bracket",
              "modifiers": ["command", "shift"]
            }
          ]
        }
      ]
    }
  ]
}`)

	if err := verifyKarabinerTerminalInvariants(path); err == nil {
		t.Fatal("expected global Ctrl-l terminal tab rewrite to fail")
	}
}

func writeKarabinerConfig(t *testing.T, content string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "karabiner.json")
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}
