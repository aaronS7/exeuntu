package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"runtime/debug"
	"time"

	"github.com/boldsoftware/exe.dev/exeuntu/internal/agentupdate"
	"github.com/boldsoftware/exe.dev/exeuntu/internal/guestllm"
	"github.com/urfave/cli/v3"
)

const appName = "exeuntu"

var gitVersion = "unknown"

var errUsage = errors.New("usage")

var updateAgent = agentupdate.Update

func main() {
	if err := run(os.Args, os.Stdout, os.Stderr); err != nil {
		if errors.Is(err, errUsage) {
			os.Exit(1)
		}
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(args []string, stdout, stderr io.Writer) error {
	return newRootCommand(stdout, stderr).Run(context.Background(), normalizeArgs(args))
}

func resolvedGitVersion() string {
	if gitVersion != "" && gitVersion != "unknown" {
		return gitVersion
	}
	if bi, ok := debug.ReadBuildInfo(); ok {
		for _, setting := range bi.Settings {
			if setting.Key == "vcs.revision" && setting.Value != "" {
				return setting.Value
			}
		}
	}
	if gitVersion != "" {
		return gitVersion
	}
	return "unknown"
}

type versionInfo struct {
	Name    string `json:"name"`
	Version string `json:"version"`
}

func newRootCommand(stdout, stderr io.Writer) *cli.Command {
	return &cli.Command{
		Name:        appName,
		Usage:       "manage Codex tooling in exeuntu",
		UsageText:   "exeuntu <command>",
		HideVersion: true,
		Writer:      stdout,
		ErrWriter:   stderr,
		Commands: []*cli.Command{
			configureCommand(),
			installCommand(),
			updateCommand(),
			versionCommand(),
		},
		OnUsageError: usageErrorHandler,
		Action: func(_ context.Context, cmd *cli.Command) error {
			showUsage(cmd, cmd.Root().ErrWriter)
			return errUsage
		},
	}
}

func normalizeArgs(args []string) []string {
	if len(args) < 2 || (args[1] != "--version" && args[1] != "-version") {
		return args
	}
	normalized := append([]string(nil), args...)
	normalized[1] = "version"
	return normalized
}

func versionCommand() *cli.Command {
	return &cli.Command{
		Name:      "version",
		Usage:     "print git version",
		UsageText: "exeuntu version [options]",
		Flags: []cli.Flag{
			&cli.BoolFlag{
				Name:  "json",
				Usage: "output version as JSON",
			},
		},
		OnUsageError: usageErrorHandler,
		Action: func(_ context.Context, cmd *cli.Command) error {
			if err := rejectArgs(cmd); err != nil {
				return err
			}
			info := versionInfo{
				Name:    appName,
				Version: resolvedGitVersion(),
			}
			if cmd.Bool("json") {
				return json.NewEncoder(cmd.Root().Writer).Encode(info)
			}
			fmt.Fprintf(cmd.Root().Writer, "%s %s\n", info.Name, info.Version)
			return nil
		},
	}
}

func configureCommand() *cli.Command {
	return &cli.Command{
		Name:      "configure",
		Usage:     "configure Codex to use the LLM integration",
		UsageText: "exeuntu configure <agent>",
		Commands: []*cli.Command{
			configureClientCommand("codex", guestllm.ClientCodex),
		},
		OnUsageError: usageErrorHandler,
		Action: func(_ context.Context, cmd *cli.Command) error {
			showUsage(cmd, cmd.Root().ErrWriter)
			return errUsage
		},
	}
}

func configureClientCommand(commandName, client string) *cli.Command {
	return &cli.Command{
		Name:      commandName,
		Usage:     llmConfigureUsage(commandName),
		UsageText: "exeuntu configure " + commandName + " [options]",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:  "home",
				Usage: "home directory override",
			},
			&cli.StringFlag{
				Name:   "integration",
				Usage:  "LLM integration name to use when more than one is available",
				Config: cli.StringConfig{TrimSpace: true},
			},
			&cli.StringFlag{
				Name:  "reflection-url",
				Usage: "reflection base URL",
				Value: guestllm.DefaultReflectionURL,
			},
		},
		OnUsageError: usageErrorHandler,
		Action: func(ctx context.Context, cmd *cli.Command) error {
			if err := rejectArgs(cmd); err != nil {
				return err
			}
			ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
			defer cancel()
			_, err := guestllm.ConfigureClient(ctx, client, guestllm.Options{
				ReflectionURL:   cmd.String("reflection-url"),
				HomeDir:         cmd.String("home"),
				Stdout:          cmd.Root().Writer,
				IntegrationName: cmd.String("integration"),
			})
			return err
		},
	}
}

func updateCommand() *cli.Command {
	return agentInstallerCommandGroup("update", "update Codex")
}

func installCommand() *cli.Command {
	return agentInstallerCommandGroup("install", "install Codex")
}

func agentInstallerCommandGroup(commandName, usage string) *cli.Command {
	return &cli.Command{
		Name:      commandName,
		Usage:     usage,
		UsageText: "exeuntu " + commandName + " <agent>",
		Commands: []*cli.Command{
			agentInstallerCommand(commandName, agentupdate.AgentCodex, commandName+" Codex", "Codex release version to install instead of latest"),
		},
		OnUsageError: usageErrorHandler,
		Action: func(_ context.Context, cmd *cli.Command) error {
			showUsage(cmd, cmd.Root().ErrWriter)
			return errUsage
		},
	}
}

func llmConfigureUsage(commandName string) string {
	if commandName == "codex" {
		return "configure Codex to use the LLM integration"
	}
	return "configure guest LLM client"
}

func agentInstallerCommand(commandName string, agent agentupdate.Agent, usage, versionUsage string) *cli.Command {
	return &cli.Command{
		Name:      string(agent),
		Usage:     usage,
		UsageText: "exeuntu " + commandName + " " + string(agent) + " [options]",
		Flags: []cli.Flag{
			&cli.StringFlag{
				Name:   "version",
				Usage:  versionUsage,
				Config: cli.StringConfig{TrimSpace: true},
			},
		},
		OnUsageError: usageErrorHandler,
		Action: func(ctx context.Context, cmd *cli.Command) error {
			if err := rejectArgs(cmd); err != nil {
				return err
			}
			ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
			defer cancel()
			_, err := updateAgent(ctx, agentupdate.Options{
				Agent:   agent,
				Version: cmd.String("version"),
				Stdout:  installerStdout(commandName, cmd),
			})
			return err
		},
	}
}

func installerStdout(commandName string, cmd *cli.Command) io.Writer {
	if commandName == "update" {
		return nil
	}
	return cmd.Root().Writer
}

func rejectArgs(cmd *cli.Command) error {
	if cmd.NArg() == 0 {
		return nil
	}
	showUsage(cmd, cmd.Root().ErrWriter)
	return errUsage
}

func usageErrorHandler(_ context.Context, cmd *cli.Command, err error, _ bool) error {
	fmt.Fprintf(cmd.Root().ErrWriter, "%v\n\n", err)
	showUsage(cmd, cmd.Root().ErrWriter)
	return errUsage
}

func showUsage(cmd *cli.Command, out io.Writer) {
	root := cmd.Root()
	oldWriter := root.Writer
	root.Writer = out
	defer func() {
		root.Writer = oldWriter
	}()

	switch {
	case cmd == root:
		_ = cli.ShowRootCommandHelp(root)
	default:
		lineage := cmd.Lineage()
		if len(lineage) > 1 {
			_ = cli.ShowCommandHelp(context.Background(), lineage[1], cmd.Name)
			return
		}
		_ = cli.ShowRootCommandHelp(root)
	}
}
