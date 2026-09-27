package main

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func writeScript(t *testing.T, dir, name, body string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte("#!/bin/sh\n"+body), 0o755); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestFingerprintExecutableResolvesSymlinkAndHashesTarget(t *testing.T) {
	dir := t.TempDir()
	real := writeScript(t, dir, "fake-ls", "echo 'fake-ls 1.2.3'\necho 'second line'\n")
	link := filepath.Join(dir, "fake-ls-link")
	if err := os.Symlink(real, link); err != nil {
		t.Fatal(err)
	}

	fingerprint := fingerprintExecutable("fake", "fake-ls", link, time.Second)
	if fingerprint.Error != "" {
		t.Fatalf("unexpected error: %s", fingerprint.Error)
	}
	wantResolved, _ := filepath.EvalSymlinks(real)
	if fingerprint.ResolvedPath != wantResolved {
		t.Fatalf("resolved_path = %q, want %q", fingerprint.ResolvedPath, wantResolved)
	}
	data, _ := os.ReadFile(real)
	sum := sha256.Sum256(data)
	if want := hex.EncodeToString(sum[:])[:12]; fingerprint.SHA256Prefix != want {
		t.Fatalf("sha256_prefix = %q, want %q", fingerprint.SHA256Prefix, want)
	}
	if fingerprint.SizeBytes != int64(len(data)) || fingerprint.ModTime == "" {
		t.Fatalf("size/mtime not recorded: %#v", fingerprint)
	}
	if fingerprint.Version != "fake-ls 1.2.3" {
		t.Fatalf("version = %q, want first line only", fingerprint.Version)
	}
	if again := fingerprintExecutable("fake", "fake-ls", link, time.Second); !reflect.DeepEqual(again, fingerprint) {
		t.Fatalf("fingerprint is not stable across runs:\n%#v\n%#v", fingerprint, again)
	}
}

func TestFingerprintExecutableOmitsVersionOnFailureOrTimeout(t *testing.T) {
	dir := t.TempDir()
	failing := writeScript(t, dir, "failing", "echo 'not a version' >&2\nexit 1\n")
	if got := fingerprintExecutable("c", "failing", failing, time.Second); got.Version != "" || got.SHA256Prefix == "" {
		t.Fatalf("failing --version should hash but not record a version: %#v", got)
	}

	hanging := writeScript(t, dir, "hanging", "sleep 5\n")
	started := time.Now()
	got := fingerprintExecutable("c", "hanging", hanging, 200*time.Millisecond)
	if elapsed := time.Since(started); elapsed > 3*time.Second {
		t.Fatalf("version probe was not bounded by its timeout: %v", elapsed)
	}
	if got.Version != "" || got.SHA256Prefix == "" {
		t.Fatalf("hanging --version should hash but not record a version: %#v", got)
	}
}

func TestFingerprintExecutableReportsMissingBinary(t *testing.T) {
	got := fingerprintExecutable("c", "ghost-ls", "", time.Second)
	if got.Error == "" || got.SHA256Prefix != "" {
		t.Fatalf("missing executable was not reported: %#v", got)
	}
}

func TestFingerprintLSPExecutablesDedupesAndSorts(t *testing.T) {
	dir := t.TempDir()
	lua := writeScript(t, dir, "lua-ls", "echo lua 3.0\n")
	marks := writeScript(t, dir, "marksman", "echo marksman 1.0\n")
	scenarios := []ScenarioResult{
		{ID: "b", Clients: []ProbeClient{{Name: "marksman", Cmd: []string{marks, "server"}, CmdPath: marks}}},
		{ID: "a", Clients: []ProbeClient{
			{Name: "lua_ls", Cmd: []string{lua}, CmdPath: lua},
			{Name: "marksman", Cmd: []string{marks, "server"}, CmdPath: marks},
			{Name: "dynamic", Initialized: true}, // function cmd: no argv, skipped
		}},
	}

	first := fingerprintLSPExecutables(scenarios)
	if len(first) != 2 || first[0].Client != "lua_ls" || first[1].Client != "marksman" {
		t.Fatalf("unexpected fingerprints: %#v", first)
	}
	if first[1].Command != marks || first[1].Version != "marksman 1.0" {
		t.Fatalf("marksman fingerprint incomplete: %#v", first[1])
	}
	if second := fingerprintLSPExecutables(scenarios); !reflect.DeepEqual(first, second) {
		t.Fatalf("fingerprints differ between runs:\n%#v\n%#v", first, second)
	}
}

func TestCompatibleLSPExecutablesRejectsBinarySwitch(t *testing.T) {
	before := []ExecutableFingerprint{{Client: "lua_ls", SHA256Prefix: "aaaaaaaaaaaa", Version: "3.13.0"}}
	same := []ExecutableFingerprint{{Client: "lua_ls", SHA256Prefix: "aaaaaaaaaaaa", Version: "3.13.0"}, {Client: "marksman", SHA256Prefix: "cc"}}
	if err := compatibleLSPExecutables(before, same); err != nil {
		t.Fatalf("identical binary rejected: %v", err)
	}
	switched := []ExecutableFingerprint{{Client: "lua_ls", SHA256Prefix: "bbbbbbbbbbbb", Version: "3.14.0"}}
	if err := compatibleLSPExecutables(before, switched); err == nil {
		t.Fatal("switched lua_ls binary was accepted as compatible")
	}
	runBefore := RunResult{Suite: "readiness", Runs: 10, Warmup: 3, Environment: Environment{LSPExecutables: before}}
	runAfter := runBefore
	runAfter.Environment.LSPExecutables = switched
	if err := compatibleRuns(runBefore, runAfter); err == nil {
		t.Fatal("compatibleRuns ignored the LSP executable change")
	}
}
