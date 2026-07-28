package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/boldsoftware/exe.dev/exeuntu/internal/agentupdate"
)

func TestVersionPrintsStampedGitVersion(t *testing.T) {
	withGitVersion(t, "test-version")

	var stdout, stderr bytes.Buffer
	if err := run([]string{"exeuntu", "version"}, &stdout, &stderr); err != nil {
		t.Fatalf("version: %v", err)
	}
	if got, want := stdout.String(), "exeuntu test-version\n"; got != want {
		t.Fatalf("stdout = %q, want %q", got, want)
	}
	if stderr.Len() != 0 {
		t.Fatalf("stderr = %q, want empty", stderr.String())
	}
}

func TestVersionJSONMode(t *testing.T) {
	withGitVersion(t, "test-version")

	for _, args := range [][]string{
		{"exeuntu", "version", "--json"},
		{"exeuntu", "--version", "--json"},
	} {
		t.Run(strings.Join(args[1:], " "), func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			if err := run(args, &stdout, &stderr); err != nil {
				t.Fatalf("run %v: %v", args, err)
			}
			var got struct {
				Name    string `json:"name"`
				Version string `json:"version"`
			}
			if err := json.Unmarshal(stdout.Bytes(), &got); err != nil {
				t.Fatalf("stdout is not json: %v\n%s", err, stdout.String())
			}
			if got.Name != "exeuntu" || got.Version != "test-version" {
				t.Fatalf("version json = %#v, want exeuntu/test-version", got)
			}
			if stderr.Len() != 0 {
				t.Fatalf("stderr = %q, want empty", stderr.String())
			}
		})
	}
}

func TestConfigureCodexWritesConfig(t *testing.T) {
	withLLMDiscoveryTransport(t)
	home := t.TempDir()
	var stdout, stderr bytes.Buffer
	if err := run([]string{"exeuntu", "configure", "codex", "--home", home}, &stdout, &stderr); err != nil {
		t.Fatalf("configure codex: %v\nstderr:\n%s", err, stderr.String())
	}
	if !strings.Contains(stdout.String(), "codex: configured") {
		t.Fatalf("stdout = %q, want codex configured", stdout.String())
	}
	if _, err := os.Stat(filepath.Join(home, ".codex", "config.toml")); err != nil {
		t.Fatalf("expected codex config: %v", err)
	}
}

func TestConfigureCodexSelectsIntegration(t *testing.T) {
	withLLMDiscoveryTransportResponses(
		t,
		[]map[string]any{
			{"name": "agentllm", "type": "llm"},
			{"name": "otherllm", "type": "llm"},
		},
		map[string][]map[string]any{
			"agentllm.int.exe.xyz": {
				{"id": "openai/gpt-5.5", "provider": "openai", "native_id": "gpt-5.5", "apis": []string{"openai_responses"}},
			},
			"otherllm.int.exe.xyz": {
				{"id": "openai/gpt-5.5", "provider": "openai", "native_id": "gpt-5.5", "apis": []string{"openai_responses"}},
			},
		},
	)
	home := t.TempDir()
	var stdout, stderr bytes.Buffer

	if err := run([]string{"exeuntu", "configure", "codex", "--home", home, "--integration", "otherllm"}, &stdout, &stderr); err != nil {
		t.Fatalf("configure codex: %v\nstderr:\n%s", err, stderr.String())
	}
	config, err := os.ReadFile(filepath.Join(home, ".codex", "config.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(config), `model_provider = "exe-otherllm"`) {
		t.Fatalf("codex config did not use selected integration:\n%s", config)
	}
}

func TestUpdateCodexIsSilentOnSuccess(t *testing.T) {
	withAgentUpdater(t, func(_ context.Context, opts agentupdate.Options) (agentupdate.Result, error) {
		if opts.Stdout != nil {
			fmt.Fprintln(opts.Stdout, "agent output")
		}
		return agentupdate.Result{Agent: opts.Agent, Version: "test-version", Path: "test-path"}, nil
	})

	var stdout, stderr bytes.Buffer
	if err := run([]string{"exeuntu", "update", "codex"}, &stdout, &stderr); err != nil {
		t.Fatalf("update codex: %v", err)
	}
	if stdout.Len() != 0 || stderr.Len() != 0 {
		t.Fatalf("stdout=%q stderr=%q, want empty", stdout.String(), stderr.String())
	}
}

func TestInstallCodexShowsUpdaterOutput(t *testing.T) {
	withAgentUpdater(t, func(_ context.Context, opts agentupdate.Options) (agentupdate.Result, error) {
		fmt.Fprintln(opts.Stdout, "agent output")
		return agentupdate.Result{Agent: opts.Agent, Version: "test-version", Path: "test-path"}, nil
	})

	var stdout, stderr bytes.Buffer
	if err := run([]string{"exeuntu", "install", "codex"}, &stdout, &stderr); err != nil {
		t.Fatalf("install codex: %v", err)
	}
	if got, want := stdout.String(), "agent output\n"; got != want {
		t.Fatalf("stdout = %q, want %q", got, want)
	}
	if stderr.Len() != 0 {
		t.Fatalf("stderr = %q, want empty", stderr.String())
	}
}

func TestOtherAgentsAreNotExposed(t *testing.T) {
	for _, args := range [][]string{
		{"exeuntu", "configure", "claude"},
		{"exeuntu", "install", "claude"},
		{"exeuntu", "update", "claude"},
		{"exeuntu", "install", "pi"},
		{"exeuntu", "update", "pi"},
	} {
		t.Run(strings.Join(args[1:], " "), func(t *testing.T) {
			var stdout, stderr bytes.Buffer
			if err := run(args, &stdout, &stderr); err == nil {
				t.Fatalf("run %v succeeded, want unsupported command", args)
			}
			if stdout.Len() != 0 {
				t.Fatalf("stdout = %q, want empty", stdout.String())
			}
		})
	}
}

func withGitVersion(t *testing.T, version string) {
	t.Helper()
	old := gitVersion
	gitVersion = version
	t.Cleanup(func() { gitVersion = old })
}

func withAgentUpdater(t *testing.T, fn func(context.Context, agentupdate.Options) (agentupdate.Result, error)) {
	t.Helper()
	old := updateAgent
	updateAgent = fn
	t.Cleanup(func() { updateAgent = old })
}

func withLLMDiscoveryTransport(t *testing.T) {
	withLLMDiscoveryTransportResponses(
		t,
		[]map[string]any{{"name": "agentllm", "type": "llm"}},
		map[string][]map[string]any{
			"agentllm.int.exe.xyz": {
				{"id": "openai/gpt-5.5", "provider": "openai", "native_id": "gpt-5.5", "apis": []string{"openai_responses"}},
			},
		},
	)
}

func withLLMDiscoveryTransportResponses(t *testing.T, integrations []map[string]any, catalogs map[string][]map[string]any) {
	t.Helper()
	oldTransport := http.DefaultTransport
	http.DefaultTransport = roundTripFunc(func(req *http.Request) (*http.Response, error) {
		var body any
		switch req.URL.Host + req.URL.Path {
		case "reflection.int.exe.xyz/integrations":
			body = map[string]any{"integrations": integrations}
		default:
			if req.URL.Path != "/models.json" {
				return nil, fmt.Errorf("unexpected discovery request: %s", req.URL.String())
			}
			models, ok := catalogs[req.URL.Host]
			if !ok {
				return nil, fmt.Errorf("unexpected discovery request: %s", req.URL.String())
			}
			body = map[string]any{"schema_version": 1, "models": models}
		}
		var buf bytes.Buffer
		if err := json.NewEncoder(&buf).Encode(body); err != nil {
			return nil, err
		}
		return &http.Response{
			StatusCode: http.StatusOK,
			Header:     make(http.Header),
			Body:       io.NopCloser(&buf),
			Request:    req,
		}, nil
	})
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(req *http.Request) (*http.Response, error) {
	return f(req)
}
