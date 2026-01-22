// Package jsonutil provides flexible JSON unmarshaling utilities.
package jsonutil

import (
	"encoding/json"
	"fmt"
)

// StringOrSlice handles JSON fields that may be either a string or []string.
// After unmarshaling, it's always a []string for consistent access.
type StringOrSlice []string

// UnmarshalJSON implements json.Unmarshaler.
func (s *StringOrSlice) UnmarshalJSON(data []byte) error {
	// Check for null first (string unmarshal succeeds for null with empty string)
	if string(data) == "null" {
		*s = nil
		return nil
	}

	// Try array first (more specific)
	var arr []string
	if err := json.Unmarshal(data, &arr); err == nil {
		*s = arr
		return nil
	}

	// Try string
	var str string
	if err := json.Unmarshal(data, &str); err == nil {
		*s = []string{str}
		return nil
	}

	return fmt.Errorf("expected string, []string, or null, got: %s", truncate(string(data), 50))
}

// First returns the first element or empty string if empty.
func (s StringOrSlice) First() string {
	if len(s) > 0 {
		return s[0]
	}
	return ""
}

// StringOrInt handles JSON fields that may be either a string or int.
// After unmarshaling, it's always a string for consistent access.
type StringOrInt string

// UnmarshalJSON implements json.Unmarshaler.
func (s *StringOrInt) UnmarshalJSON(data []byte) error {
	// Try string first
	var str string
	if err := json.Unmarshal(data, &str); err == nil {
		*s = StringOrInt(str)
		return nil
	}

	// Try int
	var num int
	if err := json.Unmarshal(data, &num); err == nil {
		*s = StringOrInt(fmt.Sprintf("%d", num))
		return nil
	}

	// Try float (some APIs return versions as floats)
	var f float64
	if err := json.Unmarshal(data, &f); err == nil {
		*s = StringOrInt(fmt.Sprintf("%v", f))
		return nil
	}

	// Try null
	var null any
	if err := json.Unmarshal(data, &null); err == nil && null == nil {
		*s = ""
		return nil
	}

	return fmt.Errorf("expected string, number, or null, got: %s", truncate(string(data), 50))
}

// String returns the string value.
func (s StringOrInt) String() string {
	return string(s)
}

// truncate shortens a string for error messages.
func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
