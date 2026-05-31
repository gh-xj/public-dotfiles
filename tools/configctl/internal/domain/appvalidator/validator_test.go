package appvalidator

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"configctl/internal/adapters/process"
	"configctl/internal/verify"
)

func TestGhosttyValidateUsesAppBundleFallback(t *testing.T) {
	runner := &ghosttyFallbackRunner{}
	result := Verify(context.Background(), "ghostty", Options{Runner: runner})

	if !result.OK {
		t.Fatalf("expected Ghostty fallback to pass: %#v", result.Diagnostics)
	}
	if len(runner.commands) != 2 {
		t.Fatalf("commands = %#v, want PATH command then app bundle fallback", runner.commands)
	}
	if runner.commands[0] != "ghostty" || runner.commands[1] != "/Applications/Ghostty.app/Contents/MacOS/ghostty" {
		t.Fatalf("commands = %#v", runner.commands)
	}
}

func TestKarabinerLintUsesHomebrewFallback(t *testing.T) {
	publicRepo := t.TempDir()
	complexModDir := filepath.Join(publicRepo, ".config", "karabiner", "assets", "complex_modifications")
	if err := os.MkdirAll(complexModDir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(complexModDir, "rules.json"), []byte(`{"rules":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}

	runner := &karabinerFallbackRunner{}
	result := verify.Runner{Checks: []verify.Check{
		karabinerLintCheck(Options{PublicRepoDir: publicRepo, Runner: runner}),
	}}.Run(context.Background(), verify.ProfileDefault)

	if !result.OK {
		t.Fatalf("expected Karabiner fallback to pass: %#v", result.Diagnostics)
	}
	if len(runner.commands) != 2 {
		t.Fatalf("commands = %#v, want PATH command then Homebrew fallback", runner.commands)
	}
	if runner.commands[0] != "karabiner_cli" || runner.commands[1] != "/opt/homebrew/bin/karabiner_cli" {
		t.Fatalf("commands = %#v", runner.commands)
	}
}

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

type ghosttyFallbackRunner struct {
	commands []string
}

func (r *ghosttyFallbackRunner) Run(_ context.Context, invocation process.Invocation) (process.Result, error) {
	r.commands = append(r.commands, invocation.Command)
	if invocation.Command == "ghostty" {
		return process.Result{}, errors.New("executable file not found")
	}
	if invocation.Command == "/Applications/Ghostty.app/Contents/MacOS/ghostty" {
		return process.Result{ExitCode: 0}, nil
	}
	return process.Result{}, errors.New("unexpected command")
}

type karabinerFallbackRunner struct {
	commands []string
}

func (r *karabinerFallbackRunner) Run(_ context.Context, invocation process.Invocation) (process.Result, error) {
	r.commands = append(r.commands, invocation.Command)
	if invocation.Command == "karabiner_cli" {
		return process.Result{}, errors.New("executable file not found")
	}
	if invocation.Command == "/opt/homebrew/bin/karabiner_cli" {
		return process.Result{ExitCode: 0}, nil
	}
	return process.Result{}, errors.New("unexpected command")
}
