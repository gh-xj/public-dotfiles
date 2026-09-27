package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadProbeResultsReadsJSONLines(t *testing.T) {
	path := filepath.Join(t.TempDir(), "probes.jsonl")
	data := "{\"schema_version\":3,\"probe\":\"vim_enter\",\"status\":\"passed\",\"elapsed_ms\":1.5,\"wall_elapsed_ms\":1.6,\"awake_elapsed_ms\":1.5}\n" +
		"{\"schema_version\":3,\"probe\":\"vim_enter\",\"status\":\"passed\",\"elapsed_ms\":2.5}\n"
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}

	results, err := readProbeResults(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(results) != 2 || results[0].ElapsedMS != 1.5 || results[1].ElapsedMS != 2.5 {
		t.Fatalf("unexpected probe results: %#v", results)
	}
	if results[0].WallElapsedMS == nil || *results[0].WallElapsedMS != 1.6 || results[0].AwakeElapsedMS == nil {
		t.Fatalf("first sample lost its clock fields: %#v", results[0])
	}
	if results[1].WallElapsedMS != nil || results[1].AwakeElapsedMS != nil {
		t.Fatalf("second sample invented clock fields: %#v", results[1])
	}
}
