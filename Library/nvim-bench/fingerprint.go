package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

const (
	// executableVersionTimeout bounds `<server> --version`; a server that does
	// not understand the flag may sit in an LSP read loop until killed.
	executableVersionTimeout = 2 * time.Second
	// executableVersionLimit caps captured version output so a chatty binary
	// cannot bloat the result.
	executableVersionLimit = 4096
	// sha256PrefixLength is the number of hex characters kept from the binary
	// digest. 48 bits is ample to distinguish builds and keeps results short.
	sha256PrefixLength = 12
)

// fingerprintLSPExecutables records the identity of every external language
// server binary the run actually launched. The harness reports each attached
// client's configured argv and the path Neovim resolved it to, so this reflects
// the process the benchmark measured rather than whatever is first on the Go
// process's PATH. Fingerprints are de-duplicated and sorted so the environment
// block is byte-stable across runs of the same suite on the same install.
func fingerprintLSPExecutables(scenarios []ScenarioResult) []ExecutableFingerprint {
	type key struct{ client, path string }
	seen := map[key]bool{}
	var fingerprints []ExecutableFingerprint
	for _, scenario := range scenarios {
		for _, client := range scenario.Clients {
			if len(client.Cmd) == 0 {
				continue
			}
			path := client.CmdPath
			if path == "" {
				if found, err := exec.LookPath(client.Cmd[0]); err == nil {
					path = found
				}
			}
			id := key{client.Name, path}
			if seen[id] {
				continue
			}
			seen[id] = true
			fingerprints = append(fingerprints, fingerprintExecutable(client.Name, client.Cmd[0], path, executableVersionTimeout))
		}
	}
	sort.Slice(fingerprints, func(i, j int) bool {
		if fingerprints[i].Client != fingerprints[j].Client {
			return fingerprints[i].Client < fingerprints[j].Client
		}
		return fingerprints[i].Path < fingerprints[j].Path
	})
	return fingerprints
}

// fingerprintExecutable describes one executable: the symlink-resolved file,
// its size, mtime, a sha256 prefix of its bytes, and the first line of
// `--version` when the binary exits cleanly within the timeout. Package
// managers often install a wrapper script (Nix, Homebrew, Mason); the hash
// then covers the wrapper, whose embedded store or version path still changes
// with the real binary, and the version line covers the rest.
func fingerprintExecutable(client, command, path string, versionTimeout time.Duration) ExecutableFingerprint {
	fingerprint := ExecutableFingerprint{Client: client, Command: command, Path: path}
	if path == "" {
		fingerprint.Error = "executable not found"
		return fingerprint
	}
	if absolute, err := filepath.Abs(path); err == nil {
		fingerprint.Path = absolute
	}
	resolved, err := filepath.EvalSymlinks(fingerprint.Path)
	if err != nil {
		fingerprint.Error = err.Error()
		return fingerprint
	}
	fingerprint.ResolvedPath = resolved
	info, err := os.Stat(resolved)
	if err != nil {
		fingerprint.Error = err.Error()
		return fingerprint
	}
	fingerprint.SizeBytes = info.Size()
	fingerprint.ModTime = info.ModTime().UTC().Format(time.RFC3339Nano)
	prefix, err := sha256Prefix(resolved)
	if err != nil {
		fingerprint.Error = err.Error()
		return fingerprint
	}
	fingerprint.SHA256Prefix = prefix
	fingerprint.Version = executableVersion(fingerprint.Path, versionTimeout)
	return fingerprint
}

func sha256Prefix(path string) (string, error) {
	file, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}
	return hex.EncodeToString(hash.Sum(nil))[:sha256PrefixLength], nil
}

// executableVersion returns the first non-empty line printed by
// `path --version`, or "" when the command fails, times out, or prints
// nothing. stdin is /dev/null so a server that ignores the flag sees EOF.
func executableVersion(path string, timeout time.Duration) string {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	command := exec.CommandContext(ctx, path, "--version")
	command.WaitDelay = 500 * time.Millisecond
	output := &limitedBuffer{limit: executableVersionLimit}
	command.Stdout = output
	command.Stderr = output
	if err := command.Run(); err != nil {
		return ""
	}
	return firstLine(output.String())
}

func firstLine(text string) string {
	for _, line := range strings.Split(text, "\n") {
		if line = strings.TrimSpace(line); line != "" {
			return line
		}
	}
	return ""
}

// limitedBuffer keeps the first limit bytes written and discards the rest.
type limitedBuffer struct {
	bytes.Buffer
	limit int
}

func (b *limitedBuffer) Write(p []byte) (int, error) {
	if remaining := b.limit - b.Len(); remaining > 0 {
		if len(p) > remaining {
			b.Buffer.Write(p[:remaining])
		} else {
			b.Buffer.Write(p)
		}
	}
	return len(p), nil
}
