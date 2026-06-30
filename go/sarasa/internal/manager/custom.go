package manager

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	osexec "os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/indrasvat/sarasa/internal/config"
	"github.com/indrasvat/sarasa/internal/logger"
	"github.com/indrasvat/sarasa/internal/process"
)

func init() {
	Register(ManagerCustom, NewCustom)
}

// Custom implements Manager for config-defined tools that do not belong to a
// standard package manager.
type Custom struct {
	opts *Options
}

const (
	customMethodCommand  = "command"
	customLatestSelf     = "self"
	customMissingSkip    = "skip"
	customMissingInstall = "install"
	customMissingFail    = "fail"
	customNotInstalled   = "not installed"
	customUnknown        = "unknown"
)

var (
	githubAPIBaseURL = "https://api.github.com"
	githubHTTPClient = &http.Client{Timeout: 15 * time.Second}
)

// NewCustom creates a custom-tool manager.
func NewCustom(opts *Options) Manager {
	return &Custom{opts: opts}
}

func (c *Custom) Name() string {
	return ManagerCustom
}

func (c *Custom) IsAvailable() bool {
	return c.opts != nil && c.opts.Config != nil && len(c.opts.Config.Custom.Tools) > 0
}

func (c *Custom) SetSkipList(packages []string) {
	c.opts.SkipList = packages
}

func (c *Custom) CheckOutdated(ctx context.Context) ([]Package, error) {
	if !c.IsAvailable() {
		return nil, nil
	}

	log := logger.WithManager(c.Name())
	var packages []Package

	for _, tool := range c.opts.Config.Custom.Tools {
		if tool.Name == "" {
			log.Warn("Skipping custom tool with empty name")
			continue
		}
		if c.opts.ShouldSkip(tool.Name) {
			continue
		}
		if !customToolAvailable(tool) {
			pkg, outdated, err := c.checkMissingTool(ctx, tool)
			if err != nil {
				return nil, err
			}
			if outdated {
				packages = append(packages, pkg)
			}
			if !outdated {
				log.Warn("Skipping unavailable custom tool", "tool", tool.Name, "binary", tool.Binary)
			}
			continue
		}

		pkg, outdated, err := c.checkTool(ctx, tool)
		if err != nil {
			log.Warn("Custom tool check failed",
				"tool", tool.Name,
				"error", err.Error(),
			)
			continue
		}
		if outdated {
			packages = append(packages, pkg)
		}
	}

	return packages, nil
}

func (c *Custom) Upgrade(ctx context.Context, dryRun bool) (*UpgradeResult, error) {
	log := logger.WithManager(c.Name())
	result := &UpgradeResult{}

	outdated, err := c.CheckOutdated(ctx)
	if err != nil {
		return nil, err
	}
	if len(outdated) == 0 {
		log.Info("No outdated custom tools", "action", "upgrade")
		return result, nil
	}

	if dryRun {
		result.Skipped = outdated
		return result, nil
	}

	outdatedByName := make(map[string]Package, len(outdated))
	for _, pkg := range outdated {
		outdatedByName[pkg.Name] = pkg
	}

	for _, tool := range c.opts.Config.Custom.Tools {
		pkg, ok := outdatedByName[tool.Name]
		if !ok {
			continue
		}
		if c.opts.ShouldSkip(tool.Name) {
			logger.LogSkipped(c.Name(), tool.Name, "in skip list")
			result.Skipped = append(result.Skipped, pkg)
			continue
		}

		if !hasAction(tool.Upgrade) {
			log.Error("Custom tool has no upgrade action", "tool", tool.Name)
			result.Failed = append(result.Failed, pkg)
			continue
		}

		start := time.Now()
		vars := map[string]string{
			"name":    tool.Name,
			"current": pkg.Current,
			"latest":  pkg.Latest,
		}
		output, err := runCustomAction(ctx, c.opts.Config.Custom.DefaultTimeout, tool.Timeout, tool.Upgrade, vars)
		duration := time.Since(start).Milliseconds()
		if err != nil {
			log.Error("Custom tool upgrade failed",
				"tool", tool.Name,
				"error", err.Error(),
				"output", output,
			)
			logger.LogUpgradeError(c.Name(), tool.Name, err, duration)
			result.Failed = append(result.Failed, pkg)
			continue
		}

		verifiedLatest := pkg.Latest
		if hasProbe(tool.Verify) {
			verifyCfg := tool.Verify
			next, verifyErr := runVersionProbe(ctx, c.opts.Config.Custom.DefaultTimeout, tool.Timeout, verifyCfg, vars)
			if verifyErr != nil {
				log.Error("Custom tool verification failed",
					"tool", tool.Name,
					"error", verifyErr.Error(),
				)
				result.Failed = append(result.Failed, pkg)
				continue
			}
			if next != "" {
				verifiedLatest = next
			}
			if pkg.Current != "" && versionsEquivalent(next, pkg.Current) && !tool.AllowUnchanged {
				err := fmt.Errorf("version unchanged after upgrade: %s", next)
				log.Error("Custom tool upgrade completed but version did not change",
					"tool", tool.Name,
					"version", next,
				)
				result.Failed = append(result.Failed, pkg)
				logger.LogUpgradeError(c.Name(), tool.Name, err, duration)
				continue
			}
		}

		recordCustomState(c.opts.Config.Custom.StateDir, tool.Name, pkg.Current, verifiedLatest, pkg.Method)
		logger.LogUpgrade(c.Name(), tool.Name, pkg.Current, verifiedLatest, duration)
		result.Upgraded = append(result.Upgraded, pkg)
	}

	return result, nil
}

func (c *Custom) Cleanup(ctx context.Context) error {
	if !c.IsAvailable() {
		return nil
	}

	for _, tool := range c.opts.Config.Custom.Tools {
		if tool.Name == "" || c.opts.ShouldSkip(tool.Name) || !customToolAvailable(tool) {
			continue
		}
		if !hasAction(tool.Cleanup) {
			continue
		}
		vars := map[string]string{"name": tool.Name}
		if _, err := runCustomAction(ctx, c.opts.Config.Custom.DefaultTimeout, tool.Timeout, tool.Cleanup, vars); err != nil {
			return fmt.Errorf("custom cleanup failed for %s: %w", tool.Name, err)
		}
	}
	return nil
}

func (c *Custom) checkTool(ctx context.Context, tool config.CustomToolConfig) (Package, bool, error) {
	current, err := currentVersion(ctx, c.opts.Config.Custom.DefaultTimeout, tool)
	if err != nil {
		return Package{}, false, err
	}

	latest, latestMethod, err := latestVersion(ctx, c.opts.Config.Custom.DefaultTimeout, tool)
	if err != nil {
		return Package{}, false, err
	}

	outdated, err := isCustomOutdated(ctx, c.opts.Config.Custom.DefaultTimeout, tool, current, latest)
	if err != nil {
		return Package{}, false, err
	}

	return Package{
		Name:    tool.Name,
		Current: displayVersion(current),
		Latest:  displayVersion(latest),
		IsMajor: isCustomMajorUpgrade(current, latest),
		Method:  methodTag(latestMethod, actionMethod(tool.Upgrade)),
	}, outdated, nil
}

func (c *Custom) checkMissingTool(ctx context.Context, tool config.CustomToolConfig) (Package, bool, error) {
	switch missingPolicy(tool) {
	case customMissingSkip:
		return Package{}, false, nil
	case customMissingFail:
		return Package{}, false, fmt.Errorf("custom tool %q missing binary %q", tool.Name, tool.Binary)
	case customMissingInstall:
		latest, latestMethod, err := latestVersion(ctx, c.opts.Config.Custom.DefaultTimeout, tool)
		if err != nil {
			return Package{}, false, err
		}
		return Package{
			Name:    tool.Name,
			Current: customNotInstalled,
			Latest:  displayVersion(latest),
			IsMajor: false,
			Method:  methodTag(latestMethod, actionMethod(tool.Upgrade)),
		}, true, nil
	default:
		return Package{}, false, fmt.Errorf("unknown missing policy %q for custom tool %q", tool.Missing, tool.Name)
	}
}

func missingPolicy(tool config.CustomToolConfig) string {
	switch strings.TrimSpace(strings.ToLower(tool.Missing)) {
	case "", customMissingSkip:
		return customMissingSkip
	case customMissingInstall:
		return customMissingInstall
	case customMissingFail:
		return customMissingFail
	default:
		return strings.TrimSpace(strings.ToLower(tool.Missing))
	}
}

func customToolAvailable(tool config.CustomToolConfig) bool {
	if tool.Binary == "" {
		return true
	}
	_, err := process.LookPath(tool.Binary)
	return err == nil
}

func currentVersion(ctx context.Context, defaultTimeout string, tool config.CustomToolConfig) (string, error) {
	probe := tool.Current
	if !hasProbe(probe) && tool.Binary != "" {
		probe = config.CustomProbeConfig{
			Argv:  []string{tool.Binary, "--version"},
			Regex: `v?[0-9]+(\.[0-9]+){1,3}([._+-][0-9A-Za-z.-]+)?`,
		}
	}
	if !hasProbe(probe) {
		return "", nil
	}
	return runVersionProbe(ctx, defaultTimeout, tool.Timeout, probe, map[string]string{"name": tool.Name})
}

func latestVersion(ctx context.Context, defaultTimeout string, tool config.CustomToolConfig) (version, method string, err error) {
	latest := tool.Latest
	switch {
	case latest.Value != "":
		return latest.Value, "pinned", nil
	case latest.GitHubRelease != "":
		version, err := latestGitHubRelease(ctx, latest.GitHubRelease)
		return version, "github-release", err
	case len(latest.Argv) > 0 || latest.Shell != "":
		probe := config.CustomProbeConfig{
			Argv:    latest.Argv,
			Shell:   latest.Shell,
			Cwd:     latest.Cwd,
			Env:     latest.Env,
			Timeout: latest.Timeout,
			Regex:   latest.Regex,
		}
		version, err := runVersionProbe(ctx, defaultTimeout, tool.Timeout, probe, map[string]string{"name": tool.Name})
		return version, customMethodCommand, err
	case latest.Mode == customUnknown || latest.Mode == customLatestSelf:
		return customLatestSelf, customLatestSelf, nil
	default:
		return "", customUnknown, nil
	}
}

func isCustomOutdated(ctx context.Context, defaultTimeout string, tool config.CustomToolConfig, current, latest string) (bool, error) {
	mode := tool.Outdated.Mode
	switch mode {
	case "", "compare", "semver":
		if current == "" || latest == "" || latest == customLatestSelf {
			return false, nil
		}
		return versionGreater(latest, current), nil
	case "always":
		return true, nil
	case "never":
		return false, nil
	case customMethodCommand:
		action := config.CustomActionConfig{
			Argv:    tool.Outdated.Argv,
			Shell:   tool.Outdated.Shell,
			Cwd:     tool.Outdated.Cwd,
			Env:     tool.Outdated.Env,
			Timeout: tool.Outdated.Timeout,
		}
		_, err := runCustomAction(ctx, defaultTimeout, tool.Timeout, action, map[string]string{
			"name":    tool.Name,
			"current": current,
			"latest":  latest,
		})
		return err == nil, nil
	default:
		return false, fmt.Errorf("unknown outdated mode %q", mode)
	}
}

func latestGitHubRelease(ctx context.Context, repo string) (string, error) {
	url := strings.TrimRight(githubAPIBaseURL, "/") + "/repos/" + repo + "/releases/latest"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Accept", "application/vnd.github+json")
	req.Header.Set("User-Agent", "sarasa")
	if token := githubToken(); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := githubHTTPClient.Do(req)
	if err != nil {
		return "", err
	}
	defer func() {
		_ = resp.Body.Close()
	}()

	if resp.StatusCode != http.StatusOK {
		statusErr := fmt.Errorf("github releases latest returned HTTP %d for %s", resp.StatusCode, repo)
		if resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden {
			if version, ghErr := latestGitHubReleaseWithGH(ctx, repo); ghErr == nil {
				return version, nil
			} else {
				return "", fmt.Errorf("%w; gh api fallback failed: %w", statusErr, ghErr)
			}
		}
		return "", statusErr
	}

	var payload struct {
		TagName string `json:"tag_name"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&payload); err != nil {
		return "", err
	}
	if payload.TagName == "" {
		return "", fmt.Errorf("github release for %s did not include tag_name", repo)
	}
	return payload.TagName, nil
}

func githubToken() string {
	for _, name := range []string{"GITHUB_TOKEN", "GH_TOKEN"} {
		if token := strings.TrimSpace(os.Getenv(name)); token != "" {
			return token
		}
	}
	return ""
}

func latestGitHubReleaseWithGH(ctx context.Context, repo string) (string, error) {
	ghPath, err := process.LookPath("gh")
	if err != nil {
		return "", err
	}
	cmd := osexec.CommandContext(ctx, ghPath, "api", "repos/"+repo+"/releases/latest", "--jq", ".tag_name")
	process.Configure(cmd, nil)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String()))
	}
	tag := strings.TrimSpace(stdout.String())
	if tag == "" {
		return "", fmt.Errorf("github release for %s did not include tag_name", repo)
	}
	return tag, nil
}

func runVersionProbe(ctx context.Context, defaultTimeout, toolTimeout string, probe config.CustomProbeConfig, vars map[string]string) (string, error) {
	action := config.CustomActionConfig{
		Argv:    probe.Argv,
		Shell:   probe.Shell,
		Cwd:     probe.Cwd,
		Env:     probe.Env,
		Timeout: probe.Timeout,
	}
	output, err := runCustomAction(ctx, defaultTimeout, toolTimeout, action, vars)
	if err != nil {
		return "", err
	}

	value := strings.TrimSpace(output)
	if probe.Regex != "" {
		re, err := regexp.Compile(probe.Regex)
		if err != nil {
			return "", fmt.Errorf("invalid version regex %q: %w", probe.Regex, err)
		}
		match := re.FindStringSubmatch(value)
		if len(match) == 0 {
			return "", fmt.Errorf("version regex %q did not match output", probe.Regex)
		}
		value = match[0]
	}
	return strings.TrimSpace(value), nil
}

func runCustomAction(ctx context.Context, defaultTimeout, toolTimeout string, action config.CustomActionConfig, vars map[string]string) (string, error) {
	if !hasAction(action) {
		return "", errors.New("missing command action")
	}

	timeout := parseCustomTimeout(firstNonEmpty(action.Timeout, toolTimeout, defaultTimeout))
	cmdCtx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	argv := substituteAll(action.Argv, vars)
	shell := substitute(action.Shell, vars)

	var cmd *osexec.Cmd
	if shell != "" {
		cmd = osexec.CommandContext(cmdCtx, "/bin/sh", "-c", shell)
	} else {
		if len(argv) == 0 {
			return "", errors.New("empty argv action")
		}
		command := argv[0]
		if path, err := process.LookPath(command); err == nil {
			command = path
		}
		cmd = osexec.CommandContext(cmdCtx, command, argv[1:]...)
	}
	if action.Cwd != "" {
		cmd.Dir = action.Cwd
	}
	extraEnv := make(map[string]string, len(action.Env))
	for key, value := range action.Env {
		extraEnv[key] = substitute(value, vars)
	}
	process.Configure(cmd, extraEnv)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	output := strings.TrimSpace(stdout.String() + stderr.String())
	if cmdCtx.Err() != nil {
		return output, fmt.Errorf("command timed out after %s: %w", timeout, cmdCtx.Err())
	}
	if err != nil {
		return output, err
	}
	return output, nil
}

func hasProbe(probe config.CustomProbeConfig) bool {
	return len(probe.Argv) > 0 || probe.Shell != ""
}

func hasAction(action config.CustomActionConfig) bool {
	return len(action.Argv) > 0 || action.Shell != ""
}

func actionMethod(action config.CustomActionConfig) string {
	switch {
	case action.Shell != "":
		return "shell"
	case len(action.Argv) > 0:
		return customMethodCommand
	default:
		return "none"
	}
}

func methodTag(parts ...string) string {
	var filtered []string
	for _, part := range parts {
		if part == "" || part == "none" || part == customUnknown {
			continue
		}
		filtered = append(filtered, part)
	}
	return strings.Join(filtered, " / ")
}

func substituteAll(values []string, vars map[string]string) []string {
	out := make([]string, len(values))
	for i, value := range values {
		out[i] = substitute(value, vars)
	}
	return out
}

func substitute(value string, vars map[string]string) string {
	for key, replacement := range vars {
		value = strings.ReplaceAll(value, "${"+key+"}", replacement)
	}
	return value
}

func parseCustomTimeout(value string) time.Duration {
	if value == "" {
		return 10 * time.Minute
	}
	d, err := time.ParseDuration(value)
	if err != nil || d <= 0 {
		return 10 * time.Minute
	}
	return d
}

func displayVersion(version string) string {
	if strings.TrimSpace(version) == "" {
		return customUnknown
	}
	return version
}

func versionsEquivalent(a, b string) bool {
	return strings.TrimPrefix(a, "v") == strings.TrimPrefix(b, "v")
}

func versionGreater(latest, current string) bool {
	latestParts, okLatest := parseVersionParts(latest)
	currentParts, okCurrent := parseVersionParts(current)
	if !okLatest || !okCurrent {
		return latest != current
	}
	for i := range latestParts {
		if latestParts[i] > currentParts[i] {
			return true
		}
		if latestParts[i] < currentParts[i] {
			return false
		}
	}
	return false
}

func isCustomMajorUpgrade(current, latest string) bool {
	latestParts, okLatest := parseVersionParts(latest)
	currentParts, okCurrent := parseVersionParts(current)
	return okLatest && okCurrent && latestParts[0] != currentParts[0]
}

func parseVersionParts(value string) ([3]int, bool) {
	var parts [3]int
	value = strings.TrimPrefix(strings.TrimSpace(value), "v")
	re := regexp.MustCompile(`^([0-9]+)(?:\.([0-9]+))?(?:\.([0-9]+))?`)
	match := re.FindStringSubmatch(value)
	if len(match) == 0 {
		return parts, false
	}
	for i := 1; i <= 3; i++ {
		if match[i] == "" {
			continue
		}
		n, err := strconv.Atoi(match[i])
		if err != nil {
			return parts, false
		}
		parts[i-1] = n
	}
	return parts, true
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func recordCustomState(stateDir, name, previous, current, method string) {
	if stateDir == "" {
		return
	}
	if err := os.MkdirAll(stateDir, 0755); err != nil {
		return
	}

	state := struct {
		Name       string    `json:"name"`
		Previous   string    `json:"previous"`
		Current    string    `json:"current"`
		Method     string    `json:"method"`
		UpgradedAt time.Time `json:"upgraded_at"`
	}{
		Name:       name,
		Previous:   previous,
		Current:    current,
		Method:     method,
		UpgradedAt: time.Now().UTC(),
	}

	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return
	}
	filename := regexp.MustCompile(`[^a-zA-Z0-9._-]+`).ReplaceAllString(name, "_") + ".json"
	_ = os.WriteFile(filepath.Join(stateDir, filename), data, 0644)
}
