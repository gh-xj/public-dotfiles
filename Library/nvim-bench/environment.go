package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

func resolveConfigHome(requested string, manifest loadedManifest) (string, error) {
	configHome := requested
	if configHome == "" {
		repoRoot, err := commandOutputIn(manifest.Dir, "git", "rev-parse", "--show-toplevel")
		if err != nil {
			return "", fmt.Errorf("resolve repository config home: %w", err)
		}
		configHome = filepath.Join(strings.TrimSpace(repoRoot), ".config")
	}
	absolute, err := filepath.Abs(configHome)
	if err != nil {
		return "", fmt.Errorf("resolve config home: %w", err)
	}
	if _, err := os.Stat(filepath.Join(absolute, "nvim", "init.lua")); err != nil {
		return "", fmt.Errorf("config home %q has no nvim/init.lua: %w", absolute, err)
	}
	return absolute, nil
}

func collectEnvironment(nvim, configHome string, manifest loadedManifest) (Environment, error) {
	nvimPath, err := exec.LookPath(nvim)
	if err != nil {
		return Environment{}, fmt.Errorf("find nvim: %w", err)
	}
	nvimPath, _ = filepath.Abs(nvimPath)
	resolved, _ := filepath.EvalSymlinks(nvimPath)
	version, err := commandOutput(nvimPath, "--version")
	if err != nil {
		return Environment{}, fmt.Errorf("read nvim version: %w", err)
	}
	hyperfinePath, err := exec.LookPath("hyperfine")
	if err != nil {
		return Environment{}, fmt.Errorf("find hyperfine: %w", err)
	}
	hyperfinePath, _ = filepath.Abs(hyperfinePath)
	hyperfineVersion, err := commandOutput(hyperfinePath, "--version")
	if err != nil {
		return Environment{}, fmt.Errorf("read hyperfine version: %w", err)
	}

	env := Environment{
		OS:               runtime.GOOS,
		Arch:             runtime.GOARCH,
		NvimRequested:    nvim,
		NvimPath:         nvimPath,
		NvimResolvedPath: resolved,
		NvimVersion:      strings.Split(strings.TrimSpace(version), "\n")[0],
		HyperfinePath:    hyperfinePath,
		HyperfineVersion: strings.TrimSpace(hyperfineVersion),
		ConfigHome:       configHome,
		ManifestSHA256:   manifest.SHA256,
	}
	configPath := filepath.Join(configHome, "nvim")
	resolvedConfigPath, err := filepath.EvalSymlinks(configPath)
	if err != nil {
		return Environment{}, fmt.Errorf("resolve Neovim config path: %w", err)
	}
	env.ConfigPath = resolvedConfigPath
	env.ConfigSHA256, err = hashTree(resolvedConfigPath, func(path string) bool {
		base := filepath.Base(path)
		return base != ".DS_Store" && base != "lazy-lock.json"
	})
	if err != nil {
		return Environment{}, fmt.Errorf("fingerprint Neovim config: %w", err)
	}
	lockPath := filepath.Join(resolvedConfigPath, "lazy-lock.json")
	if data, readErr := os.ReadFile(lockPath); readErr == nil {
		sum := sha256.Sum256(data)
		env.LazyLockSHA256 = hex.EncodeToString(sum[:])
	}
	env.HarnessSHA256, err = hashBenchmarkHarness(manifest.Dir)
	if err != nil {
		return Environment{}, fmt.Errorf("fingerprint benchmark harness: %w", err)
	}
	if runtime.GOOS == "darwin" {
		env.OSVersion, _ = commandOutput("sw_vers", "-productVersion")
		env.CPU, _ = commandOutput("sysctl", "-n", "machdep.cpu.brand_string")
		env.OSVersion = strings.TrimSpace(env.OSVersion)
		env.CPU = strings.TrimSpace(env.CPU)
	}
	repoRoot, err := commandOutputIn(manifest.Dir, "git", "rev-parse", "--show-toplevel")
	if err == nil {
		repoRoot = strings.TrimSpace(repoRoot)
		env.GitCommit, _ = commandOutputIn(repoRoot, "git", "rev-parse", "HEAD")
		env.GitCommit = strings.TrimSpace(env.GitCommit)
		status, _ := commandOutputIn(repoRoot, "git", "status", "--porcelain")
		env.GitDirty = strings.TrimSpace(status) != ""
	}
	return env, nil
}

func hashBenchmarkHarness(root string) (string, error) {
	return hashTree(root, func(path string) bool {
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return false
		}
		relative = filepath.ToSlash(relative)
		if strings.HasPrefix(relative, "fixtures/") {
			return true
		}
		return filepath.Ext(path) == ".go" || relative == "harness.lua" || relative == "scenarios.json" ||
			relative == "go.mod" || relative == "go.sum"
	})
}

func hashTree(root string, include func(string) bool) (string, error) {
	type entry struct {
		path string
		data []byte
	}
	var entries []entry
	err := filepath.WalkDir(root, func(path string, item os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if item.IsDir() {
			if item.Name() == "bin" {
				return filepath.SkipDir
			}
			return nil
		}
		if !item.Type().IsRegular() || !include(path) {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		entries = append(entries, entry{path: filepath.ToSlash(relative), data: data})
		return nil
	})
	if err != nil {
		return "", err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].path < entries[j].path })
	hash := sha256.New()
	for _, item := range entries {
		hash.Write([]byte(item.path))
		hash.Write([]byte{0})
		hash.Write(item.data)
		hash.Write([]byte{0})
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}
