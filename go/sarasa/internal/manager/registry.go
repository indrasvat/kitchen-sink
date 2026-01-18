package manager

import (
	"fmt"
	"sync"
)

var (
	registry = make(map[string]func(*Options) Manager)
	mu       sync.RWMutex
)

// Register registers a manager factory function.
func Register(name string, factory func(*Options) Manager) {
	mu.Lock()
	defer mu.Unlock()
	registry[name] = factory
}

// Get returns a manager by name.
func Get(name string, opts *Options) (Manager, error) {
	mu.RLock()
	defer mu.RUnlock()

	factory, ok := registry[name]
	if !ok {
		return nil, fmt.Errorf("unknown manager: %s", name)
	}

	return factory(opts), nil
}

// List returns all registered manager names.
func List() []string {
	mu.RLock()
	defer mu.RUnlock()

	names := make([]string, 0, len(registry))
	for name := range registry {
		names = append(names, name)
	}
	return names
}

// Available returns all available (installed) managers.
func Available(opts *Options) []Manager {
	mu.RLock()
	defer mu.RUnlock()

	var managers []Manager
	for _, factory := range registry {
		m := factory(opts)
		if m.IsAvailable() {
			managers = append(managers, m)
		}
	}
	return managers
}

// GetMultiple returns multiple managers by name.
func GetMultiple(names []string, opts *Options) ([]Manager, error) {
	var managers []Manager
	for _, name := range names {
		m, err := Get(name, opts)
		if err != nil {
			return nil, err
		}
		if !m.IsAvailable() {
			continue // Skip unavailable managers silently
		}
		managers = append(managers, m)
	}
	return managers, nil
}
