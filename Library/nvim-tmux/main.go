// nvim-tmux is the macOS URL handler for `nvim-tmux://` links.
//
// URL shape: nvim-tmux:///abs/path/to/file.md?session=SESSION&window=WINDOW
//
// On invocation it ensures the tmux session, window, and an nvim pane for
// the file all exist, then switches the most-recently-active tmux client
// (≈ the last-focused Ghostty window) to that pane. This guarantees the
// macOS-frontmost Ghostty window shows the target when `open -a Ghostty`
// raises the app.
//
// Policy: NEVER spawn a new Ghostty window/instance. Past incidents with
// `open -na` and AppleScript cmd+n corrupted xj's multi-session tmux
// layout. See AGENTS.md in this directory.
package main

import (
	"cmp"
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
)

const logPath = "/tmp/nvim-tmux.log"

// Request is a validated click. The URL is the API.
type Request struct {
	Path    string // absolute, symlink-resolved
	Session string
	Window  string
	Line    int // 0 = no cursor anchor
	Col     int // 0 = column not specified
}

// Target is an addressable tmux coordinate. WindowIdx and PaneIdx are
// the numeric identifiers tmux uses in its target-spec grammar.
type Target struct {
	Session   string
	WindowIdx int
	PaneIdx   int
}

func (t Target) Win() string  { return fmt.Sprintf("%s:%d", t.Session, t.WindowIdx) }
func (t Target) Pane() string { return fmt.Sprintf("%s:%d.%d", t.Session, t.WindowIdx, t.PaneIdx) }

// exitError lets run() return errors with a specific exit code without
// collapsing the distinction to an int return.
type exitError struct {
	code int
	err  error
}

func (e *exitError) Error() string { return e.err.Error() }
func (e *exitError) Unwrap() error { return e.err }

func usageErr(format string, a ...any) error {
	return &exitError{code: 2, err: fmt.Errorf(format, a...)}
}

func main() {
	// LaunchServices (Godspeed, Chrome) strips PATH to launchd's default,
	// which omits /opt/homebrew/bin where tmux lives. Terminal `open`
	// masked the bug by inheriting the shell's PATH.
	os.Setenv("PATH", "/opt/homebrew/bin:/usr/local/bin:"+os.Getenv("PATH"))
	configureLogger()

	err := run(os.Args[1:])
	if err == nil {
		return
	}
	slog.Error("handler failed", "err", err)
	var ee *exitError
	if errors.As(err, &ee) {
		os.Exit(ee.code)
	}
	os.Exit(1)
}

func configureLogger() {
	var w = os.Stderr
	if f, err := os.Create(logPath); err == nil {
		w = f
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(w, &slog.HandlerOptions{Level: slog.LevelDebug})))
}

func run(args []string) error {
	req, err := parseRequest(args)
	if err != nil {
		return err
	}
	slog.Info("parsed", "path", req.Path, "session", req.Session, "window", req.Window)

	target, err := ensureTarget(req)
	if err != nil {
		return err
	}

	navigate(target)

	if err := exec.Command("open", "-a", "Ghostty").Run(); err != nil {
		return fmt.Errorf("open Ghostty: %w", err)
	}
	return nil
}

// parseRequest validates args[0] as an nvim-tmux URL and returns the
// canonicalized request. Side effect: user-facing notification on error.
func parseRequest(args []string) (Request, error) {
	if len(args) < 1 {
		notify("nvim-tmux: missing URL argument")
		return Request{}, usageErr("missing URL")
	}
	raw := args[0]
	slog.Info("invoked", "url", raw)

	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "nvim-tmux" {
		notify("nvim-tmux: malformed URL (expected nvim-tmux://...)")
		return Request{}, usageErr("parse %q: %w", raw, err)
	}
	q := u.Query()
	session, window := q.Get("session"), q.Get("window")
	if session == "" || window == "" {
		notify("nvim-tmux: URL needs ?session=X&window=Y")
		return Request{}, usageErr("session and window required")
	}
	line, _ := strconv.Atoi(q.Get("line"))
	col, _ := strconv.Atoi(q.Get("col"))

	path := u.Path
	if strings.HasPrefix(path, "/~/") {
		path = filepath.Join(os.Getenv("HOME"), path[3:])
	}
	return Request{
		Path: canonical(path), Session: session, Window: window,
		Line: line, Col: col,
	}, nil
}

// ensureTarget makes the session, named window, and an nvim pane for
// req.Path all exist. Reuses an existing nvim pane in the target window
// if one is already editing the file.
func ensureTarget(req Request) (Target, error) {
	t := Target{Session: req.Session}

	// Can't use `new-session -A` here: when the session already exists,
	// `-A` attaches, which fails in non-tty contexts with "open terminal
	// failed: not a terminal". Instead, try to create; if the create
	// fails but the session now exists (racing fire, or we just didn't
	// see it in hasSession), consider it success.
	if !hasSession(req.Session) {
		if err := tmuxRun("new-session", "-d", "-s", req.Session); err != nil {
			if !hasSession(req.Session) {
				return t, fmt.Errorf("create session: %w", err)
			}
		} else {
			slog.Info("created session", "name", req.Session)
		}
	}

	winIdx, err := findWindow(req.Session, req.Window)
	if err != nil {
		return t, err
	}
	if winIdx < 0 {
		winIdx, err = createWindow(req.Session, req.Window)
		if err != nil {
			return t, err
		}
		slog.Info("created window", "name", req.Window, "idx", winIdx)
	}
	t.WindowIdx = winIdx

	paneIdx, err := findPaneWithFile(t.Win(), req.Path)
	if err != nil {
		return t, err
	}
	if paneIdx < 0 {
		paneIdx, err = spawnPane(t.Win(), nvimCmd(req))
		if err != nil {
			return t, err
		}
		slog.Info("spawned pane", "pane", paneIdx, "line", req.Line, "col", req.Col)
	} else {
		// Note: we don't replay line/col anchors into an existing nvim.
		// That would require nvim RPC or tmux send-keys gymnastics; the
		// user sees the nvim in whatever cursor state it already has.
		slog.Info("reusing pane", "pane", paneIdx)
	}
	t.PaneIdx = paneIdx
	return t, nil
}

// navigate yanks the most-recently-active client to target. Rationale:
// macOS `open -a Ghostty` raises the frontmost Ghostty window, and that
// window's tmux client IS the most-recently-active one. Yanking it
// guarantees the raised window is showing the target.
func navigate(t Target) {
	tty := mostRecentClientTTY()
	if tty == "" {
		slog.Info("no tmux clients; focusing Ghostty without yank")
		return
	}
	// switch-client only accepts a session as -t; window and pane
	// require separate select-* calls.
	_ = tmuxRun("switch-client", "-c", tty, "-t", t.Session)
	_ = tmuxRun("select-window", "-t", t.Win())
	_ = tmuxRun("select-pane", "-t", t.Pane())
	slog.Info("yanked driver", "tty", tty, "pane", t.Pane())
}

// ---- tmux helpers ----

func tmuxRun(args ...string) error {
	return exec.Command("tmux", args...).Run()
}

func tmuxOut(args ...string) (string, error) {
	out, err := exec.Command("tmux", args...).Output()
	return strings.TrimSpace(string(out)), err
}

func hasSession(name string) bool {
	return tmuxRun("has-session", "-t", "="+name) == nil
}

// findWindow returns the index of the window named `name` in `session`,
// or -1 if no such window exists.
func findWindow(session, name string) (int, error) {
	out, err := tmuxOut("list-windows", "-t", session, "-F", "#I\t#W")
	if err != nil {
		return -1, fmt.Errorf("list-windows: %w", err)
	}
	for _, line := range nonEmptyLines(out) {
		idxStr, winName, _ := strings.Cut(line, "\t")
		if winName == name {
			idx, _ := strconv.Atoi(idxStr)
			return idx, nil
		}
	}
	return -1, nil
}

// createWindow runs `new-window -P -F '#I'` which creates the window
// detached and prints its index. Avoids races vs re-listing.
func createWindow(session, name string) (int, error) {
	out, err := tmuxOut("new-window", "-t", session+":", "-d", "-n", name, "-P", "-F", "#I")
	if err != nil {
		return -1, fmt.Errorf("new-window: %w", err)
	}
	idx, err := strconv.Atoi(out)
	if err != nil {
		return -1, fmt.Errorf("parse new-window idx %q: %w", out, err)
	}
	return idx, nil
}

// findPaneWithFile walks every pane in `target` running nvim and
// returns the pane index whose nvim argv resolves to `absPath`.
// Returns -1 when no pane matches.
func findPaneWithFile(target, absPath string) (int, error) {
	out, err := tmuxOut("list-panes", "-t", target, "-F", "#{pane_tty}\t#{pane_index}\t#{pane_current_command}")
	if err != nil {
		return -1, fmt.Errorf("list-panes: %w", err)
	}
	for _, line := range nonEmptyLines(out) {
		parts := strings.SplitN(line, "\t", 3)
		if len(parts) < 3 || parts[2] != "nvim" {
			continue
		}
		tty := strings.TrimPrefix(parts[0], "/dev/")
		if pid := nvimPIDOnTTY(tty); pid != 0 && nvimHasFile(pid, absPath) {
			idx, _ := strconv.Atoi(parts[1])
			return idx, nil
		}
	}
	return -1, nil
}

// spawnPane splits target with a detached pane running `cmd`,
// returning the new pane's index.
func spawnPane(targetWin, cmd string) (int, error) {
	out, err := tmuxOut("split-window", "-t", targetWin, "-d", "-P", "-F", "#{pane_index}", cmd)
	if err != nil {
		return -1, fmt.Errorf("split-window: %w", err)
	}
	idx, err := strconv.Atoi(out)
	if err != nil {
		return -1, fmt.Errorf("parse split-window idx %q: %w", out, err)
	}
	return idx, nil
}

// nvimCmd builds the shell command string that the new pane runs.
// Honors ?line= and ?col= by prefixing the appropriate `+` or `-c`
// arguments; both are optional.
func nvimCmd(req Request) string {
	quoted := shellQuote(req.Path)
	switch {
	case req.Line > 0 && req.Col > 0:
		return fmt.Sprintf("nvim -c %s %s",
			shellQuote(fmt.Sprintf("call cursor(%d, %d)", req.Line, req.Col)),
			quoted)
	case req.Line > 0:
		return fmt.Sprintf("nvim +%d %s", req.Line, quoted)
	default:
		return "nvim " + quoted
	}
}

// mostRecentClientTTY returns the tty of the client with the largest
// client_activity timestamp (≈ the last-focused Ghostty window).
// Empty string when no clients are attached.
func mostRecentClientTTY() string {
	out, err := tmuxOut("list-clients", "-F", "#{client_activity}\t#{client_tty}")
	if err != nil || out == "" {
		return ""
	}
	type row struct {
		activity int64
		tty      string
	}
	var rows []row
	for _, line := range nonEmptyLines(out) {
		actStr, tty, ok := strings.Cut(line, "\t")
		if !ok {
			continue
		}
		a, _ := strconv.ParseInt(actStr, 10, 64)
		rows = append(rows, row{a, tty})
	}
	if len(rows) == 0 {
		return ""
	}
	best := slices.MaxFunc(rows, func(a, b row) int { return cmp.Compare(a.activity, b.activity) })
	return best.tty
}

// ---- ps helpers ----

func nvimPIDOnTTY(tty string) int {
	out, err := exec.Command("ps", "-t", tty, "-o", "pid=,command=").Output()
	if err != nil {
		return 0
	}
	for _, line := range nonEmptyLines(strings.TrimSpace(string(out))) {
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[1] == "nvim" {
			pid, _ := strconv.Atoi(fields[0])
			return pid
		}
	}
	return 0
}

// nvimHasFile reports whether the nvim process `pid` was launched with
// a file argument whose realpath equals `abs`. Paths with spaces are
// not reliably detectable — see AGENTS.md.
func nvimHasFile(pid int, abs string) bool {
	out, err := exec.Command("ps", "-o", "args=", "-p", strconv.Itoa(pid)).Output()
	if err != nil {
		return false
	}
	fields := strings.Fields(strings.TrimSpace(string(out)))
	for i, arg := range fields {
		if i == 0 || strings.HasPrefix(arg, "-") {
			continue
		}
		if canonical(arg) == abs {
			return true
		}
	}
	return false
}

// ---- path + misc helpers ----

// canonical returns the realpath of path when possible, falling back to
// resolving parent symlinks when the file doesn't exist (macOS /tmp →
// /private/tmp).
func canonical(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	if resolved, err := filepath.EvalSymlinks(abs); err == nil {
		return resolved
	}
	dir, base := filepath.Split(abs)
	if resolved, err := filepath.EvalSymlinks(filepath.Clean(dir)); err == nil {
		return filepath.Join(resolved, base)
	}
	return abs
}

// nonEmptyLines splits on \n and drops empty lines so callers don't
// special-case `strings.Split("", "\n") == [""]`.
func nonEmptyLines(s string) []string {
	if s == "" {
		return nil
	}
	lines := strings.Split(s, "\n")
	return slices.DeleteFunc(lines, func(l string) bool { return l == "" })
}

// shellQuote wraps s for POSIX sh single-quoting, matching what tmux
// passes to sh -c when it runs a shell-command arg.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// notify pops a macOS notification via osascript. Used for user-facing
// usage errors from the URL scheme dispatch (where stderr is invisible).
func notify(msg string) {
	script := fmt.Sprintf(`display notification %q with title "nvim-tmux"`, msg)
	_ = exec.Command("osascript", "-e", script).Run()
}
