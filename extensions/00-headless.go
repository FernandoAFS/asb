//go:build ignore

package main

import (
	"encoding/json"
	"fmt"
	"strings"
	"sync"

	"kit/ext"
)

// 00-headless.go — a toggle that keeps an unattended agent from freezing on
// interactive prompts.
//
// Kit has no built-in "never ask me anything" switch. The prompts that stall a
// worker come from other extensions: the ask_question tool shows a modal and
// waits for an answer, and sudo-handler.go intercepts a shell call and waits
// for a password. A worker left running unattended therefore blocks until
// someone answers.
//
// This extension blocks those calls before the prompt-producing extensions are
// ever consulted, so an agent running unattended fails fast instead of
// freezing. When active it blocks:
//
//   - ask_question              — the model is told to decide for itself or stop.
//   - a shell command using sudo — denied before sudo-handler.go can prompt.
//
// It deliberately does NOT police destructive commands (rm -rf, mkfs, dd,
// chmod 777, writes to /dev). Those do not prompt on their own, and inside a
// kwt sandbox bwrap already denies everything outside the writable Target directory —
// a read-only bind cannot be removed and the sandbox root is a throwaway tmpfs.
// Blocking them here would only add false positives (e.g. `rm -rf node_modules`)
// for commands the sandbox was always going to contain.
//
// Toggle it with /headless (or ctrl+alt+h). Start already active with:
//
//	KIT_OPT_HEADLESS=true kit -e 00-headless.go
//
// or in .kit.yml:
//
//	options:
//	  headless: true
//
// kwt sets KIT_OPT_HEADLESS=true for every kit launch, so a worker starts
// headless by default and can be made interactive again with /headless off.
//
// Load order matters: Kit runs OnToolCall handlers in extension load order and
// the first Block wins. The 00- prefix sorts this file ahead of every
// conventionally named extension, so it is consulted before sudo-handler.go and
// any future prompt-producing extension. Keep the name.

var (
	mu       sync.RWMutex
	headless bool
)

// Init registers the /headless command, the ctrl+alt+h shortcut, the
// KIT_OPT_HEADLESS option, and the tool-call guard.
func Init(api ext.API) {
	api.RegisterOption(ext.OptionDef{
		Name:        "headless",
		Description: "Start in headless mode: block interactive questions and sudo prompts",
		Default:     "false",
	})

	api.RegisterShortcut(ext.ShortcutDef{
		Key:         "ctrl+alt+h",
		Description: "Toggle headless mode (block interactive prompts)",
	}, func(ctx ext.Context) {
		toggle(ctx)
	})

	api.RegisterCommand(ext.CommandDef{
		Name:        "headless",
		Description: "Toggle headless mode: block questions and sudo prompts (ctrl+alt+h)",
		Execute: func(args string, ctx ext.Context) (string, error) {
			switch strings.ToLower(strings.TrimSpace(args)) {
			case "", "toggle":
				toggle(ctx)
			case "on", "true", "yes", "1":
				setActive(ctx, true)
			case "off", "false", "no", "0":
				setActive(ctx, false)
			default:
				return "", fmt.Errorf("usage: /headless [on|off]")
			}
			return "", nil
		},
	})

	// Honour the option (env var or config) when the session starts.
	api.OnSessionStart(func(_ ext.SessionStartEvent, ctx ext.Context) {
		if truthy(ctx.GetOption("headless")) {
			setActive(ctx, true)
		}
	})

	// Tell the model the rules so it does not keep reaching for blocked tools.
	api.OnBeforeAgentStart(func(_ ext.BeforeAgentStartEvent, ctx ext.Context) *ext.BeforeAgentStartResult {
		if !isActive() {
			return nil
		}
		prompt := `You are in HEADLESS MODE.

Nobody is watching this session. You cannot ask the user questions or request a
sudo password, so those are blocked before they can run.

Instead of asking, use your best judgment: read the code, pick the most
reasonable option, state the assumption you made, and continue. Do not use sudo.
If a decision is genuinely the user's to make, stop and write out what you need
decided — do not call ask_question.`
		return &ext.BeforeAgentStartResult{SystemPrompt: &prompt}
	})

	api.OnToolCall(func(tc ext.ToolCallEvent, _ ext.Context) *ext.ToolCallResult {
		if !isActive() {
			return nil
		}

		// Questions: block the ask_question tool before its modal can open.
		if tc.ToolName == "ask_question" {
			return &ext.ToolCallResult{
				Block: true,
				Reason: "interactive questions are disabled (headless mode); decide from the code and context, " +
					"or stop and report what you need decided",
			}
		}

		if !isShellTool(tc.ToolName) {
			return nil
		}

		var input struct {
			Command string `json:"command"`
		}
		if err := json.Unmarshal([]byte(tc.Input), &input); err != nil {
			return nil
		}

		// sudo runs before the sandbox can fail it: sudo-handler.go prompts for
		// a password at tool-call time, so this must block first.
		if containsSudo(input.Command) {
			return &ext.ToolCallResult{
				Block: true,
				Reason: "sudo is disabled (headless mode) because it would block on a password prompt: " +
					truncate(input.Command, 80) + " — run it outside the sandbox instead",
			}
		}

		return nil
	})
}

func toggle(ctx ext.Context) {
	mu.Lock()
	headless = !headless
	active := headless
	mu.Unlock()
	applyMode(ctx, active)
}

func setActive(ctx ext.Context, active bool) {
	mu.Lock()
	headless = active
	mu.Unlock()
	applyMode(ctx, active)
}

func isActive() bool {
	mu.RLock()
	defer mu.RUnlock()
	return headless
}

// applyMode reflects the new state in the status bar and prints a notice. It is
// safe to call with the state already true, so OnSessionStart can restore the
// option without a prior toggle.
func applyMode(ctx ext.Context, active bool) {
	if active {
		ctx.SetStatus("headless-mode", "HEADLESS (no questions)", 10)
		ctx.PrintInfo("Headless mode ON — questions and sudo prompts are blocked.\nUse /headless (ctrl+alt+h) to toggle off.")
	} else {
		ctx.RemoveStatus("headless-mode")
		ctx.PrintInfo("Headless mode OFF — interactive questions and prompts re-enabled.")
	}
}

func truthy(value string) bool {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "true", "1", "yes", "on":
		return true
	}
	return false
}

func isShellTool(name string) bool {
	return name == "shell" || name == "bash"
}

// containsSudo reports whether a command runs sudo. sudo-handler.go only
// matches a handful of literal patterns, and a sudo call it misses falls
// through to the real terminal, which then prompts for a password. This splits
// the command into shell runs and inspects the command word of each run, so it
// catches pipes, chaining, newlines, command substitution, and absolute paths
// such as /usr/bin/sudo without flagging sudo when it is merely an argument
// (`grep sudo README.md`).
func containsSudo(command string) bool {
	for _, run := range splitShellRuns(command) {
		if runRunsSudo(run) {
			return true
		}
	}
	return false
}

// splitShellRuns breaks a command at the separators that start a new command.
// Double-character separators are listed before their single-character
// counterparts; NewReplacer takes the longest match at each position.
func splitShellRuns(command string) []string {
	replacer := strings.NewReplacer(
		"&&", "\n",
		"||", "\n",
		"$(", "\n",
		"|", "\n",
		";", "\n",
		"&", "\n",
		"(", "\n",
		")", "\n",
		"`", "\n",
		"\r", "\n",
	)
	return strings.Split(replacer.Replace(command), "\n")
}

// runRunsSudo reports whether one shell run invokes sudo as its command. It
// skips leading VAR=value assignments, environment/prefix commands, and flags,
// then checks the first real word.
func runRunsSudo(run string) bool {
	for _, field := range strings.Fields(run) {
		token := strings.Trim(field, "`'\"(){}[];|&<>!")
		if token == "" || strings.HasPrefix(token, "-") || isAssignment(token) {
			continue
		}
		if isCommandPrefix(baseName(token)) {
			continue
		}
		return baseName(token) == "sudo"
	}
	return false
}

func isAssignment(token string) bool {
	eq := strings.Index(token, "=")
	return eq > 0
}

func baseName(token string) string {
	if i := strings.LastIndex(token, "/"); i >= 0 {
		return token[i+1:]
	}
	return token
}

// isCommandPrefix lists commands that wrap another command; the word after one
// of these is still the command word.
func isCommandPrefix(name string) bool {
	switch name {
	case "command", "env", "exec", "eval", "nohup", "nice", "time", "xargs":
		return true
	}
	return false
}

func truncate(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max-3] + "..."
}
