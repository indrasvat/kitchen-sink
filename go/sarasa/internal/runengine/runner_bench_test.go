package runengine

import (
	"context"
	"fmt"
	"testing"

	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/manager"
)

func BenchmarkRunnerFakeManagers(b *testing.B) {
	if err := logger.Init(logger.Config{Dir: b.TempDir()}); err != nil {
		b.Fatalf("init logger: %v", err)
	}
	b.Cleanup(func() { _ = logger.Close() })

	for _, count := range []int{1, 4, 8} {
		b.Run(fmt.Sprintf("managers_%d", count), func(b *testing.B) {
			managers := make([]manager.Manager, 0, count)
			for i := 0; i < count; i++ {
				managers = append(managers, &fakeManager{
					name: fmt.Sprintf("manager-%d", i),
					result: &manager.UpgradeResult{
						Upgraded: []manager.Package{{Name: "pkg"}},
					},
				})
			}
			runner := Runner{SkipCleanup: true}
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				output := runner.Run(context.Background(), managers)
				if !output.Success {
					b.Fatalf("runner failed: %+v", output)
				}
			}
		})
	}
}
