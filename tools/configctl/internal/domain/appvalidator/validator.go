package appvalidator

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"configctl/internal/adapters/process"
	"configctl/internal/domain/repo"
	"configctl/internal/report"
	"configctl/internal/verify"
)

type Options struct {
	PublicRepoDir string
	Runner        process.Runner
}

func Verify(ctx context.Context, name string, opts Options) verify.Result {
	resolved := resolveOptions(opts)
	checks := checksFor(name, resolved)
	return verify.Runner{Checks: checks}.Run(ctx, verify.ProfileDefault)
}

func Summary(name string, result verify.Result) string {
	if result.OK {
		return fmt.Sprintf("app %s verify: %d/%d checks passing", name, result.Counts.Passed, result.Counts.Total)
	}
	return fmt.Sprintf("app %s verify failed: %d required check(s) failed", name, result.Counts.RequiredFailed)
}

func checksFor(name string, opts Options) []verify.Check {
	switch name {
	case "nvim":
		return []verify.Check{commandCheck("app.nvim.startup", "Neovim headless startup", "nvim", []string{"--headless", "+qa"}, "", opts)}
	case "lazygit":
		return []verify.Check{
			commandCheck("app.lazygit.yaml", "Lazygit YAML", "ruby", []string{"-ryaml", "-e", `YAML.load_file(".config/lazygit/config.yml")`}, opts.PublicRepoDir, opts),
			commandCheck("app.lazygit.binary", "lazygit binary", "lazygit", []string{"--version"}, "", opts),
			commandCheck("app.lazygit.delta", "delta binary", "delta", []string{"--version"}, "", opts),
			commandCheck("app.lazygit.difft", "difft binary", "difft", []string{"--version"}, "", opts),
			commandCheck("app.lazygit.gh", "GitHub CLI binary", "gh", []string{"--version"}, "", opts),
		}
	case "ghostty":
		return []verify.Check{ghosttyValidateCheck(opts)}
	case "karabiner":
		return []verify.Check{
			karabinerLintCheck(opts),
			karabinerTerminalInvariantCheck(opts),
		}
	case "tmux":
		return []verify.Check{tmuxCheck(opts)}
	case "terminal":
		var checks []verify.Check
		checks = append(checks, checksFor("ghostty", opts)...)
		checks = append(checks, checksFor("karabiner", opts)...)
		checks = append(checks, checksFor("tmux", opts)...)
		return checks
	default:
		return []verify.Check{{
			ID:       "app.unknown",
			Name:     "unknown app validator",
			Required: true,
			Run: func(context.Context) verify.CheckResult {
				return verify.CheckResult{
					OK:      false,
					Summary: "unknown app validator",
					Diagnostics: []report.Diagnostic{{
						Severity: "error",
						Code:     "app.validator_unknown",
						Message:  "unknown app validator " + name,
					}},
				}
			},
		}}
	}
}

func ghosttyValidateCheck(opts Options) verify.Check {
	const id = "app.ghostty.validate"
	const name = "Ghostty config"
	candidates := []string{
		"ghostty",
		"/Applications/Ghostty.app/Contents/MacOS/ghostty",
	}
	return verify.Check{
		ID:       id,
		Name:     name,
		Required: true,
		Run: func(ctx context.Context) verify.CheckResult {
			var missing []string
			for _, command := range candidates {
				result, err := opts.Runner.Run(ctx, process.Invocation{Command: command, Args: []string{"+validate-config"}})
				if err != nil {
					missing = append(missing, fmt.Sprintf("%s: %s", command, err.Error()))
					continue
				}
				if result.ExitCode != 0 {
					message := strings.TrimSpace(result.Stderr)
					if message == "" {
						message = strings.TrimSpace(result.Stdout)
					}
					if message == "" {
						message = fmt.Sprintf("%s exited %d", command, result.ExitCode)
					}
					return checkFailure(id, message, command)
				}
				return verify.CheckResult{OK: true, Summary: name + " ok"}
			}
			return checkFailure(id, strings.Join(missing, "; "), strings.Join(candidates, ", "))
		},
	}
}

func commandCheck(id string, name string, command string, args []string, dir string, opts Options) verify.Check {
	return verify.Check{
		ID:       id,
		Name:     name,
		Required: true,
		Run: func(ctx context.Context) verify.CheckResult {
			result, err := opts.Runner.Run(ctx, process.Invocation{Command: command, Args: args, Dir: dir})
			if err != nil {
				return checkFailure(id, err.Error(), "")
			}
			if result.ExitCode != 0 {
				message := strings.TrimSpace(result.Stderr)
				if message == "" {
					message = strings.TrimSpace(result.Stdout)
				}
				if message == "" {
					message = fmt.Sprintf("%s exited %d", command, result.ExitCode)
				}
				return checkFailure(id, message, "")
			}
			return verify.CheckResult{OK: true, Summary: name + " ok"}
		},
	}
}

func karabinerLintCheck(opts Options) verify.Check {
	candidates := []string{
		"karabiner_cli",
		"/opt/homebrew/bin/karabiner_cli",
		"/usr/local/bin/karabiner_cli",
		"/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli",
	}
	return verify.Check{
		ID:       "app.karabiner.lint",
		Name:     "Karabiner complex modifications",
		Required: true,
		Run: func(ctx context.Context) verify.CheckResult {
			pattern := filepath.Join(opts.PublicRepoDir, ".config", "karabiner", "assets", "complex_modifications", "*.json")
			files, err := filepath.Glob(pattern)
			if err != nil {
				return checkFailure("app.karabiner.lint", err.Error(), pattern)
			}
			if len(files) == 0 {
				return checkFailure("app.karabiner.lint", "no complex modification files found", pattern)
			}
			var diagnostics []report.Diagnostic
			for _, file := range files {
				result, command, err := runFirstAvailable(ctx, opts.Runner, candidates, []string{"--lint-complex-modifications", file})
				if err != nil {
					diagnostics = append(diagnostics, report.Diagnostic{Severity: "error", Code: "app.karabiner.lint_failed", Message: err.Error(), Path: file})
					continue
				}
				if result.ExitCode != 0 {
					message := strings.TrimSpace(result.Stderr)
					if message == "" {
						message = strings.TrimSpace(result.Stdout)
					}
					if message == "" {
						message = fmt.Sprintf("%s exited %d", command, result.ExitCode)
					}
					diagnostics = append(diagnostics, report.Diagnostic{Severity: "error", Code: "app.karabiner.lint_failed", Message: message, Path: file})
				}
			}
			if len(diagnostics) > 0 {
				return verify.CheckResult{OK: false, Summary: "Karabiner lint failed", Diagnostics: diagnostics}
			}
			return verify.CheckResult{OK: true, Summary: fmt.Sprintf("Karabiner lint ok: %d file(s)", len(files))}
		},
	}
}

func runFirstAvailable(ctx context.Context, runner process.Runner, candidates []string, args []string) (process.Result, string, error) {
	var missing []string
	for _, command := range candidates {
		result, err := runner.Run(ctx, process.Invocation{Command: command, Args: args})
		if err != nil {
			missing = append(missing, fmt.Sprintf("%s: %s", command, err.Error()))
			continue
		}
		return result, command, nil
	}
	return process.Result{}, "", fmt.Errorf("%s", strings.Join(missing, "; "))
}

func karabinerTerminalInvariantCheck(opts Options) verify.Check {
	return verify.Check{
		ID:       "app.karabiner.terminal_invariant",
		Name:     "Karabiner terminal key invariants",
		Required: true,
		Run: func(context.Context) verify.CheckResult {
			paths := []string{
				filepath.Join(opts.PublicRepoDir, ".config", "karabiner", "assets", "complex_modifications", "xjm-rules.json"),
				filepath.Join(opts.PublicRepoDir, ".config", "karabiner", "karabiner.json"),
			}
			for _, path := range paths {
				if err := verifyKarabinerTerminalInvariants(path); err != nil {
					return checkFailure("app.karabiner.terminal_invariant", err.Error(), path)
				}
			}
			return verify.CheckResult{OK: true, Summary: "Karabiner terminal invariants ok"}
		},
	}
}

func tmuxCheck(opts Options) verify.Check {
	script := fmt.Sprintf(`set -eu
socket="configctl-verify-terminal-$$"
cleanup() {
  tmux -L "$socket" kill-server >/dev/null 2>&1 || true
}
trap cleanup EXIT

tmux -L "$socket" -f /dev/null new-session -d -s verify-terminal 'sleep 60'
tmux -L "$socket" source-file %q

for key in M-b M-d M-D M-f M-w M-z; do
  if tmux -L "$socket" list-keys -T root "$key" >/dev/null 2>&1; then
    printf 'unexpected root tmux binding claims %%s\n' "$key" >&2
    tmux -L "$socket" list-keys -T root "$key" >&2
    exit 1
  fi
done

tmux -L "$socket" list-keys -T prefix '|' >/dev/null
tmux -L "$socket" list-keys -T prefix '_' >/dev/null
tmux -L "$socket" list-keys -T prefix X >/dev/null
tmux -L "$socket" list-keys -T prefix z >/dev/null
tmux -L "$socket" list-keys -T prefix E >/dev/null
tmux -L "$socket" list-keys -T prefix J | grep -q 'easyjump.tmux/easyjump.py'

for table in copy-mode copy-mode-vi; do
  if tmux -L "$socket" list-keys -T "$table" C-J >/dev/null 2>&1; then
    printf 'unexpected EasyJump copy-mode binding in %%s C-J\n' "$table" >&2
    tmux -L "$socket" list-keys -T "$table" C-J >&2
    exit 1
  fi
  tmux -L "$socket" list-keys -T "$table" C-j | grep -q 'select-pane -D'
done
`, filepath.Join(opts.PublicRepoDir, ".tmux.conf"))
	return commandCheck("app.tmux.bindings", "tmux bindings", "sh", []string{"-c", script}, opts.PublicRepoDir, opts)
}

func verifyKarabinerTerminalInvariants(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	var value any
	if err := json.Unmarshal(data, &value); err != nil {
		return err
	}
	for _, item := range walkObjects(value) {
		source, ok := item["from"].(map[string]any)
		if !ok {
			continue
		}
		targets, ok := item["to"].([]any)
		if !ok {
			continue
		}
		sourceKey, _ := source["key_code"].(string)
		if sourceKey != "h" && sourceKey != "l" {
			continue
		}
		if !hasMandatoryModifier(source, "control") {
			continue
		}
		for _, rawTarget := range targets {
			target, ok := rawTarget.(map[string]any)
			if !ok {
				continue
			}
			targetKey, _ := target["key_code"].(string)
			if !isTerminalTabRewrite(sourceKey, targetKey) {
				continue
			}
			if hasStringListValues(target["modifiers"], "command", "shift") && !limitedToChrome(item) {
				return fmt.Errorf("Karabiner rewrites Ctrl-%s in %s", sourceKey, path)
			}
		}
	}
	return nil
}

func walkObjects(value any) []map[string]any {
	var objects []map[string]any
	switch typed := value.(type) {
	case map[string]any:
		objects = append(objects, typed)
		for _, child := range typed {
			objects = append(objects, walkObjects(child)...)
		}
	case []any:
		for _, child := range typed {
			objects = append(objects, walkObjects(child)...)
		}
	}
	return objects
}

func hasMandatoryModifier(source map[string]any, modifier string) bool {
	modifiers, ok := source["modifiers"].(map[string]any)
	if !ok {
		return false
	}
	return hasStringListValues(modifiers["mandatory"], modifier)
}

func hasStringListValues(value any, required ...string) bool {
	values, ok := value.([]any)
	if !ok {
		return false
	}
	seen := map[string]struct{}{}
	for _, raw := range values {
		if text, ok := raw.(string); ok {
			seen[text] = struct{}{}
		}
	}
	for _, item := range required {
		if _, ok := seen[item]; !ok {
			return false
		}
	}
	return true
}

func limitedToChrome(item map[string]any) bool {
	conditions, ok := item["conditions"].([]any)
	if !ok {
		return false
	}
	for _, raw := range conditions {
		condition, ok := raw.(map[string]any)
		if !ok || condition["type"] != "frontmost_application_if" {
			continue
		}
		bundleIDs, ok := condition["bundle_identifiers"].([]any)
		if ok && len(bundleIDs) == 1 && bundleIDs[0] == `^com\.google\.Chrome$` {
			return true
		}
	}
	return false
}

func isTerminalTabRewrite(sourceKey string, targetKey string) bool {
	return (sourceKey == "h" && targetKey == "open_bracket") || (sourceKey == "l" && targetKey == "close_bracket")
}

func checkFailure(code string, message string, path string) verify.CheckResult {
	return verify.CheckResult{
		OK:      false,
		Summary: message,
		Diagnostics: []report.Diagnostic{{
			Severity: "error",
			Code:     code,
			Message:  message,
			Path:     path,
		}},
	}
}

func resolveOptions(opts Options) Options {
	if opts.Runner == nil {
		opts.Runner = process.ExecRunner{}
	}
	if opts.PublicRepoDir == "" {
		if registryPath, err := repo.DefaultRegistryPath(); err == nil {
			opts.PublicRepoDir = repo.PublicRootFromRegistry(registryPath)
		}
	}
	return opts
}
