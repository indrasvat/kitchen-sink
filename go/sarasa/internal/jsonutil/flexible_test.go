package jsonutil_test

import (
	"encoding/json"
	"testing"

	"github.com/indrasvat/sarasa/internal/jsonutil"
)

func TestStringOrSlice_String(t *testing.T) {
	var s jsonutil.StringOrSlice
	err := json.Unmarshal([]byte(`"hello"`), &s)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(s) != 1 || s[0] != "hello" {
		t.Errorf("expected [hello], got %v", s)
	}
	if s.First() != "hello" {
		t.Errorf("First() = %q, want %q", s.First(), "hello")
	}
}

func TestStringOrSlice_Array(t *testing.T) {
	var s jsonutil.StringOrSlice
	err := json.Unmarshal([]byte(`["a", "b", "c"]`), &s)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(s) != 3 {
		t.Errorf("expected 3 elements, got %d", len(s))
	}
	if s.First() != "a" {
		t.Errorf("First() = %q, want %q", s.First(), "a")
	}
}

func TestStringOrSlice_Null(t *testing.T) {
	var s jsonutil.StringOrSlice
	err := json.Unmarshal([]byte(`null`), &s)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	// null unmarshals to empty slice, which is functionally equivalent to nil for our purposes
	if len(s) != 0 {
		t.Errorf("expected empty, got %v", s)
	}
	if s.First() != "" {
		t.Errorf("First() on null = %q, want empty", s.First())
	}
}

func TestStringOrSlice_EmptyArray(t *testing.T) {
	var s jsonutil.StringOrSlice
	err := json.Unmarshal([]byte(`[]`), &s)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(s) != 0 {
		t.Errorf("expected empty, got %v", s)
	}
	if s.First() != "" {
		t.Errorf("First() on empty = %q, want empty", s.First())
	}
}

func TestStringOrSlice_Invalid(t *testing.T) {
	var s jsonutil.StringOrSlice
	err := json.Unmarshal([]byte(`123`), &s)
	if err == nil {
		t.Error("expected error for number, got nil")
	}
}

func TestStringOrSlice_InStruct(t *testing.T) {
	type TestStruct struct {
		Versions jsonutil.StringOrSlice `json:"versions"`
	}

	tests := []struct {
		name         string
		input        string
		expectedLen  int
		expectedVals []string
	}{
		{"string", `{"versions": "1.0.0"}`, 1, []string{"1.0.0"}},
		{"array", `{"versions": ["1.0.0", "2.0.0"]}`, 2, []string{"1.0.0", "2.0.0"}},
		{"null", `{"versions": null}`, 0, nil},
		{"missing", `{}`, 0, nil},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var s TestStruct
			err := json.Unmarshal([]byte(tt.input), &s)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if len(s.Versions) != tt.expectedLen {
				t.Errorf("expected len=%d, got %d (values: %v)", tt.expectedLen, len(s.Versions), s.Versions)
			}
			for i, v := range tt.expectedVals {
				if i < len(s.Versions) && s.Versions[i] != v {
					t.Errorf("expected versions[%d]=%s, got %s", i, v, s.Versions[i])
				}
			}
		})
	}
}

func TestStringOrInt_String(t *testing.T) {
	var s jsonutil.StringOrInt
	err := json.Unmarshal([]byte(`"1.2.3"`), &s)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if s.String() != "1.2.3" {
		t.Errorf("expected 1.2.3, got %s", s.String())
	}
}

func TestStringOrInt_Int(t *testing.T) {
	var s jsonutil.StringOrInt
	err := json.Unmarshal([]byte(`42`), &s)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if s.String() != "42" {
		t.Errorf("expected 42, got %s", s.String())
	}
}

func TestStringOrInt_Float(t *testing.T) {
	var s jsonutil.StringOrInt
	err := json.Unmarshal([]byte(`3.14`), &s)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if s.String() != "3.14" {
		t.Errorf("expected 3.14, got %s", s.String())
	}
}

func TestStringOrInt_Null(t *testing.T) {
	var s jsonutil.StringOrInt
	err := json.Unmarshal([]byte(`null`), &s)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if s.String() != "" {
		t.Errorf("expected empty, got %s", s.String())
	}
}

func TestStringOrInt_Invalid(t *testing.T) {
	var s jsonutil.StringOrInt
	err := json.Unmarshal([]byte(`["array"]`), &s)
	if err == nil {
		t.Error("expected error for array, got nil")
	}
}
