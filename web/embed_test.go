package web

import (
	"io"
	"testing"
)

func TestDistFS(t *testing.T) {
	fsys, err := DistFS()
	if err != nil {
		t.Fatalf("DistFS() returned error: %v", err)
	}

	f, err := fsys.Open("index.html")
	if err != nil {
		t.Fatalf("failed to open index.html: %v", err)
	}
	defer f.Close()

	content, err := io.ReadAll(f)
	if err != nil {
		t.Fatalf("failed to read index.html: %v", err)
	}

	if len(content) == 0 {
		t.Errorf("expected non-empty index.html")
	}
}
