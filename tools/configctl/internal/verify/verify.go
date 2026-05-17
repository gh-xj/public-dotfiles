package verify

import (
	"context"
	"fmt"
	"time"

	"configctl/internal/report"
)

type Profile string

const (
	ProfileDefault Profile = "default"
	ProfileFull    Profile = "full"
)

type Check struct {
	ID       string
	Name     string
	Required bool
	FullOnly bool
	Run      func(context.Context) CheckResult
}

type CheckResult struct {
	ID          string              `json:"id"`
	Name        string              `json:"name"`
	OK          bool                `json:"ok"`
	Required    bool                `json:"required"`
	Summary     string              `json:"summary"`
	DurationMS  int64               `json:"duration_ms"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type Result struct {
	Profile     Profile             `json:"profile"`
	OK          bool                `json:"ok"`
	Checks      []CheckResult       `json:"checks"`
	Counts      Counts              `json:"counts"`
	Diagnostics []report.Diagnostic `json:"diagnostics"`
}

type Counts struct {
	Total          int `json:"total"`
	Passed         int `json:"passed"`
	Failed         int `json:"failed"`
	Required       int `json:"required"`
	RequiredFailed int `json:"required_failed"`
	Optional       int `json:"optional"`
	OptionalFailed int `json:"optional_failed"`
}

type Runner struct {
	Checks []Check
}

func ParseProfile(value string) (Profile, error) {
	switch value {
	case "", string(ProfileDefault):
		return ProfileDefault, nil
	case string(ProfileFull):
		return ProfileFull, nil
	default:
		return "", fmt.Errorf("unsupported verify profile %q", value)
	}
}

func (r Runner) Run(ctx context.Context, profile Profile) Result {
	result := Result{Profile: profile, OK: true}
	for _, check := range r.Checks {
		if check.FullOnly && profile != ProfileFull {
			continue
		}
		start := time.Now()
		checkResult := check.Run(ctx)
		checkResult.ID = check.ID
		checkResult.Name = check.Name
		checkResult.Required = check.Required
		checkResult.DurationMS = time.Since(start).Milliseconds()
		result.Checks = append(result.Checks, checkResult)
		result.Counts.Total++
		if check.Required {
			result.Counts.Required++
		} else {
			result.Counts.Optional++
		}
		if checkResult.OK {
			result.Counts.Passed++
			continue
		}
		result.Counts.Failed++
		result.Diagnostics = append(result.Diagnostics, checkResult.Diagnostics...)
		if check.Required {
			result.Counts.RequiredFailed++
			result.OK = false
		} else {
			result.Counts.OptionalFailed++
		}
	}
	return result
}
