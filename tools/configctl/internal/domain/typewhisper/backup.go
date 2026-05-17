package typewhisper

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"time"
)

func BackupStores(storeDir string, repoRoot string, now time.Time) (string, error) {
	if repoRoot == "" {
		repoRoot = "."
	}
	backupDir := filepath.Join(repoRoot, ".install-backups", "typewhisper", now.Format("20060102-150405"))
	if err := os.MkdirAll(backupDir, 0o755); err != nil {
		return "", err
	}
	for _, base := range []string{"dictionary.store", "snippets.store"} {
		for _, suffix := range []string{"", "-wal", "-shm"} {
			source := filepath.Join(storeDir, base+suffix)
			if _, err := os.Stat(source); err != nil {
				if os.IsNotExist(err) {
					continue
				}
				return "", err
			}
			if err := copyFile(source, filepath.Join(backupDir, base+suffix)); err != nil {
				return "", fmt.Errorf("copy %s: %w", source, err)
			}
		}
	}
	return backupDir, nil
}

func copyFile(source string, destination string) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	info, err := input.Stat()
	if err != nil {
		return err
	}
	output, err := os.OpenFile(destination, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, info.Mode())
	if err != nil {
		return err
	}
	defer output.Close()
	_, err = io.Copy(output, input)
	return err
}
