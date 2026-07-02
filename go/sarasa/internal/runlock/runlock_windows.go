//go:build windows

package runlock

import "os"

func lockFile(*os.File) error {
	return nil
}

func unlockFile(*os.File) error {
	return nil
}
