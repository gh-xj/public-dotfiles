package filesystem

import "os"

type FileSystem interface {
	Stat(path string) (os.FileInfo, error)
	Lstat(path string) (os.FileInfo, error)
	ReadFile(path string) ([]byte, error)
	WriteFile(path string, data []byte, perm os.FileMode) error
	MkdirAll(path string, perm os.FileMode) error
	ReadDir(path string) ([]os.DirEntry, error)
	Symlink(oldname string, newname string) error
	Readlink(path string) (string, error)
	Rename(oldpath string, newpath string) error
}

type OS struct{}

func (OS) Stat(path string) (os.FileInfo, error) {
	return os.Stat(path)
}

func (OS) Lstat(path string) (os.FileInfo, error) {
	return os.Lstat(path)
}

func (OS) ReadFile(path string) ([]byte, error) {
	return os.ReadFile(path)
}

func (OS) WriteFile(path string, data []byte, perm os.FileMode) error {
	return os.WriteFile(path, data, perm)
}

func (OS) MkdirAll(path string, perm os.FileMode) error {
	return os.MkdirAll(path, perm)
}

func (OS) ReadDir(path string) ([]os.DirEntry, error) {
	return os.ReadDir(path)
}

func (OS) Symlink(oldname string, newname string) error {
	return os.Symlink(oldname, newname)
}

func (OS) Readlink(path string) (string, error) {
	return os.Readlink(path)
}

func (OS) Rename(oldpath string, newpath string) error {
	return os.Rename(oldpath, newpath)
}
