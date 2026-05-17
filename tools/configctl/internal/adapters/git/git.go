package git

import (
	"context"
	"strings"

	"configctl/internal/adapters/process"
)

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

type CLIInspector struct {
	Runner process.Runner
}

func (i CLIInspector) DirtySummary(ctx context.Context, repoRoot string) (DirtySummary, error) {
	runner := i.Runner
	if runner == nil {
		runner = process.ExecRunner{}
	}
	summary := DirtySummary{RepoRoot: repoRoot}
	branch, err := runner.Run(ctx, process.Invocation{
		Command: "git",
		Args:    []string{"-C", repoRoot, "branch", "--show-current"},
	})
	if err != nil {
		return summary, err
	}
	if branch.ExitCode == 0 {
		summary.Branch = strings.TrimSpace(branch.Stdout)
	}
	status, err := runner.Run(ctx, process.Invocation{
		Command: "git",
		Args:    []string{"-C", repoRoot, "status", "--porcelain=v1"},
	})
	if err != nil {
		return summary, err
	}
	if status.ExitCode != 0 {
		return summary, nil
	}
	for _, line := range strings.Split(status.Stdout, "\n") {
		if len(line) < 2 {
			continue
		}
		x := line[0]
		y := line[1]
		if x == '?' && y == '?' {
			summary.Untracked++
			continue
		}
		if x != ' ' {
			summary.Staged++
		}
		if y != ' ' {
			summary.Changed++
		}
	}
	return summary, nil
}
