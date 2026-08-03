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

func TestValidateManifestRequiresExpectedRenderNamespace(t *testing.T) {
	manifest := Manifest{
		SchemaVersion: manifestSchemaVersion,
		Harness:       "harness.lua",
		Scenarios: []Scenario{
			{
				ID:          "render",
				Description: "Render readiness",
				Probe:       "render_ready",
				TimeoutMS:   1000,
			},
		},
	}

	err := validateManifest(manifest)
	if err == nil || !strings.Contains(err.Error(), "expected_namespace") {
		t.Fatalf("validateManifest error = %v, want expected_namespace error", err)
	}
}

func TestValidateManifestRejectsInvalidLSPClientScope(t *testing.T) {
	manifest := Manifest{
		SchemaVersion: manifestSchemaVersion,
		Harness:       "harness.lua",
		Scenarios: []Scenario{
			{
				ID:             "lsp",
				Description:    "LSP readiness",
				Probe:          "lsp_ready",
				ExpectedClient: "lua_ls",
				ClientScope:    "workspace",
				TimeoutMS:      1000,
			},
		},
	}

	err := validateManifest(manifest)
	if err == nil || !strings.Contains(err.Error(), "client_scope") {
		t.Fatalf("validateManifest error = %v, want client_scope error", err)
	}
}
