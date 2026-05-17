package reporoot

type Root struct {
	Name string
	Path string
}

type Finder interface {
	Find(start string) (Root, error)
}
