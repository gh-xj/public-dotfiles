package typewhisper

import (
	"context"
	"os/exec"
)

func IsRunning(ctx context.Context) bool {
	return exec.CommandContext(ctx, "pgrep", "-x", "TypeWhisper").Run() == nil
}
