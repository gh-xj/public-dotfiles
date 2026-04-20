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
// layout. See ~/.claude/projects/.../feedback-ghostty-new-window-forbidden.md.
package main

import (
	"errors"
	"fmt"
	"log/slog"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

const logPath = "/tmp/nvim-tmux.log"

func main() {
	logFile, err := os.Create(logPath)
	if err != nil {
		logFile = os.Stderr
	}
	defer logFile.Close()
	slog.SetDefault(slog.New(slog.NewTextHandler(logFile, &slog.HandlerOptions{Level: slog.LevelDebug})))

	code, err := run(os.Args)
	if err != nil {
		slog.Error("handler failed", "err", err)
	}
	os.Exit(code)
}

func run(args []string) (int, error) {
	if len(args) < 2 {
		notify("nvim-tmux: missing URL argument")
		return 2, errors.New("missing URL arg")
	}
	raw := args[1]
	slog.Info("invoked", "url", raw)

	u, err := url.Parse(raw)
	if err != nil || u.Scheme != "nvim-tmux" {
		notify("nvim-tmux: malformed URL (expected nvim-tmux://...)")
		return 2, fmt.Errorf("parse %q: %w", raw, err)
	}

	path := u.Path
	if strings.HasPrefix(path, "/~/") {
		path = filepath.Join(os.Getenv("HOME"), path[3:])
	}
	abs := canonical(path)

	session := u.Query().Get("session")
	window := u.Query().Get("window")
	if session == "" || window == "" {
		notify("nvim-tmux: URL needs ?session=X&window=Y")
		return 2, errors.New("session/window required")
	}
	slog.Info("parsed", "path", abs, "session", session, "window", window)

	if !hasSession(session) {
		if err := tmux("new-session", "-d", "-s", session); err != nil {
			return 1, fmt.Errorf("create session: %w", err)
		}
		slog.Info("created session", "name", session)
	}

	winIdx, err := findWindow(session, window)
	if err != nil {
		return 1, err
	}
	if winIdx < 0 {
		if err := tmux("new-window", "-t", session+":", "-d", "-n", window); err != nil {
			return 1, fmt.Errorf("create window: %w", err)
		}
		winIdx, _ = findWindow(session, window)
		slog.Info("created window", "name", window, "idx", winIdx)
	}
	targetWin := fmt.Sprintf("%s:%d", session, winIdx)

	paneIdx, err := findPaneWithFile(targetWin, abs)
	if err != nil {
		return 1, err
	}
	if paneIdx < 0 {
		if err := tmux("split-window", "-t", targetWin, "-d", "nvim "+shellQuote(abs)); err != nil {
			return 1, fmt.Errorf("split-window: %w", err)
		}
		paneIdx, _ = newestPane(targetWin)
		slog.Info("spawned pane", "pane", paneIdx)
	} else {
		slog.Info("reusing pane", "pane", paneIdx)
	}
	targetPane := fmt.Sprintf("%s.%d", targetWin, paneIdx)

	if tty := mostRecentClientTTY(); tty != "" {
		// switch-client yanks the driver client to target session (consent-given
		// via URL). select-window + select-pane then navigate within it.
		_ = tmux("switch-client", "-c", tty, "-t", session)
		_ = tmux("select-window", "-t", targetWin)
		_ = tmux("select-pane", "-t", targetPane)
		slog.Info("yanked driver", "tty", tty, "pane", targetPane)
	} else {
		slog.Info("no tmux clients; focusing Ghostty without yank")
	}

	if err := exec.Command("open", "-a", "Ghostty").Run(); err != nil {
		return 1, fmt.Errorf("open Ghostty: %w", err)
	}
	return 0, nil
}

// canonical returns the realpath of path when possible, falling back to
// an absolute form when the file doesn't exist (macOS /tmp → /private/tmp).
func canonical(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	if resolved, err := filepath.EvalSymlinks(abs); err == nil {
		return resolved
	}
	// file missing — resolve parent dir symlinks, keep basename
	dir, base := filepath.Split(abs)
	if resolved, err := filepath.EvalSymlinks(filepath.Clean(dir)); err == nil {
		return filepath.Join(resolved, base)
	}
	return abs
}

func tmux(args ...string) error {
	return exec.Command("tmux", args...).Run()
}

func tmuxOutput(args ...string) (string, error) {
	out, err := exec.Command("tmux", args...).Output()
	return strings.TrimSpace(string(out)), err
}

func hasSession(name string) bool {
	return exec.Command("tmux", "has-session", "-t", "="+name).Run() == nil
}

func findWindow(session, name string) (int, error) {
	out, err := tmuxOutput("list-windows", "-t", session, "-F", "#I\t#W")
	if err != nil {
		return -1, fmt.Errorf("list-windows: %w", err)
	}
	for _, line := range strings.Split(out, "\n") {
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) == 2 && parts[1] == name {
			idx, _ := strconv.Atoi(parts[0])
			return idx, nil
		}
	}
	return -1, nil
}

func newestPane(target string) (int, error) {
	out, err := tmuxOutput("list-panes", "-t", target, "-F", "#{pane_index}")
	if err != nil {
		return -1, err
	}
	lines := strings.Split(out, "\n")
	idx, _ := strconv.Atoi(lines[len(lines)-1])
	return idx, nil
}

func findPaneWithFile(target, absPath string) (int, error) {
	want := absPath
	out, err := tmuxOutput("list-panes", "-t", target, "-F", "#{pane_tty}\t#{pane_index}\t#{pane_current_command}")
	if err != nil {
		return -1, fmt.Errorf("list-panes: %w", err)
	}
	for _, line := range strings.Split(out, "\n") {
		parts := strings.SplitN(line, "\t", 3)
		if len(parts) < 3 || parts[2] != "nvim" {
			continue
		}
		tty := strings.TrimPrefix(parts[0], "/dev/")
		pid := nvimPIDOnTTY(tty)
		if pid == 0 {
			continue
		}
		argv, err := psArgs(pid)
		if err != nil {
			continue
		}
		fields := strings.Fields(argv)
		for i, arg := range fields {
			if i == 0 || strings.HasPrefix(arg, "-") {
				continue
			}
			if canonical(arg) == want {
				idx, _ := strconv.Atoi(parts[1])
				return idx, nil
			}
		}
	}
	return -1, nil
}

func nvimPIDOnTTY(tty string) int {
	out, err := exec.Command("ps", "-t", tty, "-o", "pid=,command=").Output()
	if err != nil {
		return 0
	}
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		fields := strings.Fields(line)
		if len(fields) >= 2 && fields[1] == "nvim" {
			pid, _ := strconv.Atoi(fields[0])
			return pid
		}
	}
	return 0
}

func psArgs(pid int) (string, error) {
	out, err := exec.Command("ps", "-o", "args=", "-p", strconv.Itoa(pid)).Output()
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func mostRecentClientTTY() string {
	out, err := tmuxOutput("list-clients", "-F", "#{client_activity}\t#{client_tty}")
	if err != nil || out == "" {
		return ""
	}
	type row struct {
		activity int64
		tty      string
	}
	var rows []row
	for _, line := range strings.Split(out, "\n") {
		parts := strings.SplitN(line, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		a, _ := strconv.ParseInt(parts[0], 10, 64)
		rows = append(rows, row{a, parts[1]})
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].activity > rows[j].activity })
	if len(rows) == 0 {
		return ""
	}
	return rows[0].tty
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func notify(msg string) {
	script := fmt.Sprintf(`display notification %q with title "nvim-tmux"`, msg)
	_ = exec.Command("osascript", "-e", script).Run()
}
