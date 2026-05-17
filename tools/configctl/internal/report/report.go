package report

import (
	"encoding/json"
	"fmt"
	"io"
)

const SchemaVersion = "configctl.v1"

type Diagnostic struct {
	Severity string `json:"severity"`
	Code     string `json:"code"`
	Message  string `json:"message"`
	Path     string `json:"path,omitempty"`
}

type Envelope struct {
	SchemaVersion string       `json:"schema_version"`
	Command       string       `json:"command"`
	OK            bool         `json:"ok"`
	Changed       bool         `json:"changed"`
	DryRun        bool         `json:"dry_run"`
	Summary       string       `json:"summary"`
	Data          any          `json:"data"`
	Diagnostics   []Diagnostic `json:"diagnostics"`
}

type ExitError struct {
	Code int
}

func (e ExitError) Error() string {
	return fmt.Sprintf("exit %d", e.Code)
}

func New(command string, ok bool, changed bool, dryRun bool, summary string, data any, diagnostics []Diagnostic) Envelope {
	if data == nil {
		data = map[string]any{}
	}
	if diagnostics == nil {
		diagnostics = []Diagnostic{}
	}
	return Envelope{
		SchemaVersion: SchemaVersion,
		Command:       command,
		OK:            ok,
		Changed:       changed,
		DryRun:        dryRun,
		Summary:       summary,
		Data:          data,
		Diagnostics:   diagnostics,
	}
}

func Write(w io.Writer, env Envelope, jsonOutput bool) error {
	if jsonOutput {
		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		return enc.Encode(env)
	}
	return WriteHuman(w, env)
}

func WriteHuman(w io.Writer, env Envelope) error {
	if env.OK {
		if _, err := fmt.Fprintln(w, env.Summary); err != nil {
			return err
		}
	} else {
		if _, err := fmt.Fprintf(w, "error: %s\n", env.Summary); err != nil {
			return err
		}
	}
	for _, diagnostic := range env.Diagnostics {
		line := fmt.Sprintf("%s[%s]: %s", diagnostic.Severity, diagnostic.Code, diagnostic.Message)
		if diagnostic.Path != "" {
			line += " (" + diagnostic.Path + ")"
		}
		if _, err := fmt.Fprintln(w, line); err != nil {
			return err
		}
	}
	return nil
}
