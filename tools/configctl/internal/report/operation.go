package report

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
	"unicode"
)

const OperationReportSchemaVersion = "configctl.operation.v1"

type OperationReport struct {
	SchemaVersion     string            `json:"schema_version"`
	Command           string            `json:"command"`
	OK                bool              `json:"ok"`
	Changed           bool              `json:"changed"`
	DryRun            bool              `json:"dry_run"`
	ReleaseEligible   bool              `json:"release_eligible"`
	Args              []string          `json:"args"`
	RepoRoots         map[string]string `json:"repo_roots"`
	TouchedPaths      []string          `json:"touched_paths"`
	Backups           []string          `json:"backups"`
	VerificationHints []string          `json:"verification_hints"`
	Diagnostics       []Diagnostic      `json:"diagnostics"`
	Redaction         RedactionMetadata `json:"redaction"`
	Metadata          map[string]any    `json:"metadata,omitempty"`
	StartedAt         string            `json:"started_at,omitempty"`
	FinishedAt        string            `json:"finished_at,omitempty"`
}

type OperationReportInput struct {
	Command           string
	OK                bool
	Changed           bool
	DryRun            bool
	ReleaseEligible   bool
	Args              []string
	RepoRoots         map[string]string
	TouchedPaths      []string
	Backups           []string
	VerificationHints []string
	Diagnostics       []Diagnostic
	Metadata          map[string]any
	StartedAt         time.Time
	FinishedAt        time.Time
}

type RedactionMetadata struct {
	Applied bool           `json:"applied"`
	Rules   []RedactionHit `json:"rules,omitempty"`
}

type RedactionHit struct {
	ArgIndex int    `json:"arg_index"`
	Rule     string `json:"rule"`
	Flag     string `json:"flag,omitempty"`
}

type ReportPathPolicy struct {
	RepoRoot     string
	ExplicitPath string
	Command      string
	Now          time.Time
}

func NewOperationReport(input OperationReportInput) OperationReport {
	args, redaction := SanitizeArgs(input.Args)
	return OperationReport{
		SchemaVersion:     OperationReportSchemaVersion,
		Command:           input.Command,
		OK:                input.OK,
		Changed:           input.Changed,
		DryRun:            input.DryRun,
		ReleaseEligible:   input.ReleaseEligible,
		Args:              args,
		RepoRoots:         copyStringMap(input.RepoRoots),
		TouchedPaths:      copySorted(input.TouchedPaths),
		Backups:           copySorted(input.Backups),
		VerificationHints: copySorted(input.VerificationHints),
		Diagnostics:       append([]Diagnostic{}, input.Diagnostics...),
		Redaction:         redaction,
		Metadata:          copyAnyMap(input.Metadata),
		StartedAt:         formatReportTime(input.StartedAt),
		FinishedAt:        formatReportTime(input.FinishedAt),
	}
}

func WriteOperationReport(path string, operation OperationReport) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(operation, "", "  ")
	if err != nil {
		return err
	}
	data = append(data, '\n')
	return os.WriteFile(path, data, 0o644)
}

func ResolveOperationReportPath(policy ReportPathPolicy) (string, error) {
	now := policy.Now
	if now.IsZero() {
		now = time.Now()
	}
	if policy.ExplicitPath != "" {
		explicit := expandHome(policy.ExplicitPath)
		if isDirectoryReportTarget(explicit) {
			return filepath.Abs(filepath.Join(explicit, reportFileName(policy.Command, now)))
		}
		return filepath.Abs(explicit)
	}
	if policy.RepoRoot == "" {
		return "", errors.New("repo root is required when report path is not explicit")
	}
	return filepath.Abs(filepath.Join(policy.RepoRoot, ".configctl", "runs", reportFileName(policy.Command, now)))
}

func SanitizeArgs(args []string) ([]string, RedactionMetadata) {
	out := append([]string{}, args...)
	var hits []RedactionHit
	for i := 0; i < len(out); i++ {
		arg := out[i]
		if key, _, ok := strings.Cut(arg, "="); ok && isSensitiveKey(key) && !strings.HasPrefix(arg, "-") {
			out[i] = key + "=[REDACTED]"
			hits = append(hits, RedactionHit{ArgIndex: i, Rule: "sensitive-assignment", Flag: key})
			continue
		}
		if !strings.HasPrefix(arg, "-") {
			continue
		}
		flag, _, hasValue := strings.Cut(arg, "=")
		if !isSensitiveKey(flag) {
			continue
		}
		if hasValue {
			out[i] = flag + "=[REDACTED]"
			hits = append(hits, RedactionHit{ArgIndex: i, Rule: "sensitive-flag-value", Flag: flag})
			continue
		}
		hits = append(hits, RedactionHit{ArgIndex: i, Rule: "sensitive-flag", Flag: flag})
		if i+1 < len(out) && !strings.HasPrefix(out[i+1], "-") {
			i++
			out[i] = "[REDACTED]"
			hits = append(hits, RedactionHit{ArgIndex: i, Rule: "sensitive-flag-value", Flag: flag})
		}
	}
	return out, RedactionMetadata{Applied: len(hits) > 0, Rules: hits}
}

func reportFileName(command string, now time.Time) string {
	name := sanitizeReportCommand(command)
	if name == "" {
		name = "operation"
	}
	return fmt.Sprintf("%s-%s.json", now.Format("20060102-150405"), name)
}

func sanitizeReportCommand(command string) string {
	command = strings.TrimSpace(command)
	var b strings.Builder
	previousDash := false
	for _, r := range command {
		allowed := unicode.IsLetter(r) || unicode.IsDigit(r) || r == '_' || r == '-'
		if allowed {
			b.WriteRune(unicode.ToLower(r))
			previousDash = false
			continue
		}
		if !previousDash {
			b.WriteByte('-')
			previousDash = true
		}
	}
	return strings.Trim(b.String(), "-")
}

func isDirectoryReportTarget(path string) bool {
	if strings.HasSuffix(path, string(filepath.Separator)) {
		return true
	}
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func isSensitiveKey(key string) bool {
	key = strings.TrimLeft(strings.ToLower(key), "-")
	key = strings.ReplaceAll(key, "_", "-")
	for _, needle := range []string{
		"api-key",
		"apikey",
		"auth",
		"bearer",
		"credential",
		"header",
		"password",
		"passwd",
		"refresh-token",
		"secret",
		"token",
	} {
		if strings.Contains(key, needle) {
			return true
		}
	}
	return false
}

func expandHome(path string) string {
	if path == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			return home
		}
	}
	if strings.HasPrefix(path, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, path[2:])
		}
	}
	return path
}

func formatReportTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}

func copySorted(values []string) []string {
	out := append([]string{}, values...)
	sort.Strings(out)
	if out == nil {
		return []string{}
	}
	return out
}

func copyStringMap(values map[string]string) map[string]string {
	out := map[string]string{}
	for key, value := range values {
		out[key] = value
	}
	return out
}

func copyAnyMap(values map[string]any) map[string]any {
	if values == nil {
		return nil
	}
	out := map[string]any{}
	for key, value := range values {
		out[key] = value
	}
	return out
}
