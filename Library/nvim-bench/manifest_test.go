package main

import (
	"strings"
	"testing"
)

func TestValidateManifestRequiresExpectedLSPClient(t *testing.T) {
	manifest := Manifest{
		SchemaVersion: manifestSchemaVersion,
		Harness:       "harness.lua",
		Scenarios: []Scenario{
			{
				ID:          "lsp",
				Description: "LSP readiness",
				Probe:       "lsp_ready",
				TimeoutMS:   1000,
			},
		},
	}

	err := validateManifest(manifest)
	if err == nil || !strings.Contains(err.Error(), "expected_client") {
		t.Fatalf("validateManifest error = %v, want expected_client error", err)
	}
}

func TestValidateManifestRejectsExpectedClientForOtherProbes(t *testing.T) {
	manifest := Manifest{
		SchemaVersion: manifestSchemaVersion,
		Harness:       "harness.lua",
		Scenarios: []Scenario{
			{
				ID:             "startup",
				Description:    "Startup readiness",
				Probe:          "vim_enter",
				ExpectedClient: "lua_ls",
				TimeoutMS:      1000,
			},
		},
	}

	err := validateManifest(manifest)
	if err == nil || !strings.Contains(err.Error(), "non-LSP") {
		t.Fatalf("validateManifest error = %v, want non-LSP error", err)
	}
}
