package ui

import "testing"

func TestManagerIconLabelPrefix(t *testing.T) {
	if got := ManagerIconLabelPrefix("skills"); got != IconSkills+" " {
		t.Fatalf("skills prefix = %q, want one-cell gap", got)
	}
	if got := ManagerIconLabelPrefix(managerCustom); got != IconCustom+" " {
		t.Fatalf("custom prefix = %q, want one-cell gap", got)
	}
}
