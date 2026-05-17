package paths

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
)

const typeWhisperLexicon = "Library/Application Support/TypeWhisper/lexicon.json"

func Expand(path string) string {
	if path == "" {
		return ""
	}
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

func TypeWhisperStoreDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return filepath.Join("~", "Library", "Application Support", "TypeWhisper")
	}
	return filepath.Join(home, "Library", "Application Support", "TypeWhisper")
}

func TypeWhisperLexiconPath() (string, error) {
	root, err := PrivateConfigRoot()
	if err != nil {
		return typeWhisperLexicon, err
	}
	return filepath.Join(root, typeWhisperLexicon), nil
}

func PrivateConfigRoot() (string, error) {
	if root, ok := privateRootFromEnv(); ok {
		return root, nil
	}
	wd, err := os.Getwd()
	if err == nil {
		if root, ok := searchUp(wd); ok {
			return root, nil
		}
		if root, ok := siblingPrivateRoot(wd); ok {
			return root, nil
		}
	}
	exe, err := os.Executable()
	if err == nil {
		if root, ok := searchUp(filepath.Dir(exe)); ok {
			return root, nil
		}
		if root, ok := siblingPrivateRoot(filepath.Dir(exe)); ok {
			return root, nil
		}
	}
	return "", errors.New("could not locate private-config root")
}

func privateRootFromEnv() (string, bool) {
	root := os.Getenv("PRIVATE_REPO_DIR")
	if root == "" {
		return "", false
	}
	abs, err := filepath.Abs(root)
	if err != nil {
		return "", false
	}
	return abs, exists(filepath.Join(abs, typeWhisperLexicon))
}

func searchUp(start string) (string, bool) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return "", false
	}
	for {
		if exists(filepath.Join(dir, typeWhisperLexicon)) && exists(filepath.Join(dir, "configctl", "home.toml")) {
			return dir, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", false
		}
		dir = parent
	}
}

func siblingPrivateRoot(start string) (string, bool) {
	publicRoot, ok := searchPublicRoot(start)
	if !ok {
		return "", false
	}
	privateRoot := filepath.Join(filepath.Dir(publicRoot), "private-config")
	return privateRoot, exists(filepath.Join(privateRoot, typeWhisperLexicon))
}

func searchPublicRoot(start string) (string, bool) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return "", false
	}
	for {
		if filepath.Base(dir) == "public-dotfiles" && exists(filepath.Join(dir, "configctl", "home.toml")) {
			return dir, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", false
		}
		dir = parent
	}
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
