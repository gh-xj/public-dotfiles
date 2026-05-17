package git

import "context"

type DirtySummary struct {
	RepoRoot  string `json:"repo_root"`
	Branch    string `json:"branch,omitempty"`
	Changed   int    `json:"changed"`
	Staged    int    `json:"staged"`
	Untracked int    `json:"untracked"`
}

type Inspector interface {
	DirtySummary(ctx context.Context, repoRoot string) (DirtySummary, error)
}
