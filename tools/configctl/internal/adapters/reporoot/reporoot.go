package reporoot

import (
	"fmt"
	"os"
	"path/filepath"
)

type Root struct {
	Name string
	Path string
}

type Finder interface {
	Find(start string) (Root, error)
}

type GitFinder struct{}

func (GitFinder) Find(start string) (Root, error) {
	if start == "" {
		wd, err := os.Getwd()
		if err != nil {
			return Root{}, err
		}
		start = wd
	}
	dir, err := filepath.Abs(start)
	if err != nil {
		return Root{}, err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, ".git")); err == nil {
			return Root{Name: filepath.Base(dir), Path: dir}, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return Root{}, fmt.Errorf("could not locate git root from %s", start)
		}
		dir = parent
	}
}
