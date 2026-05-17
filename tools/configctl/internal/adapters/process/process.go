package process

import (
	"bytes"
	"context"
	"os"
	"os/exec"
)

type Invocation struct {
	Command string
	Args    []string
	Dir     string
	Env     []string
}

type Result struct {
	Stdout   string
	Stderr   string
	ExitCode int
}

type Runner interface {
	Run(ctx context.Context, invocation Invocation) (Result, error)
}

type ExecRunner struct{}

func (ExecRunner) Run(ctx context.Context, invocation Invocation) (Result, error) {
	cmd := exec.CommandContext(ctx, invocation.Command, invocation.Args...)
	cmd.Dir = invocation.Dir
	if len(invocation.Env) > 0 {
		cmd.Env = append(os.Environ(), invocation.Env...)
	}
	var stdout bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	exitCode := -1
	if cmd.ProcessState != nil {
		exitCode = cmd.ProcessState.ExitCode()
	}
	result := Result{
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		ExitCode: exitCode,
	}
	if err != nil {
		if cmd.ProcessState != nil {
			return result, nil
		}
		return result, err
	}
	return result, nil
}
