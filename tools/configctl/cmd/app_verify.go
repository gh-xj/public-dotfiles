package cmd

import (
	"context"

	appctx "configctl/internal/app"
	"configctl/internal/domain/appvalidator"
	"configctl/internal/report"
)

type NvimCmd struct {
	Verify NvimVerifyCmd `cmd:"" help:"verify Neovim startup"`
}

type LazygitCmd struct {
	Verify LazygitVerifyCmd `cmd:"" help:"verify Lazygit config and helpers"`
}

type GhosttyCmd struct {
	Verify GhosttyVerifyCmd `cmd:"" help:"verify Ghostty config"`
}

type TmuxCmd struct {
	Verify TmuxVerifyCmd `cmd:"" help:"verify tmux terminal bindings"`
}

type KarabinerCmd struct {
	Verify KarabinerVerifyCmd `cmd:"" help:"verify Karabiner config"`
}

type TerminalCmd struct {
	Verify TerminalVerifyCmd `cmd:"" help:"verify terminal app workflow"`
}

type appVerifyOptions struct {
	PublicRepo string `name:"public-repo" help:"public-dotfiles repo path" type:"path"`
}

type NvimVerifyCmd struct{ appVerifyOptions }
type LazygitVerifyCmd struct{ appVerifyOptions }
type GhosttyVerifyCmd struct{ appVerifyOptions }
type TmuxVerifyCmd struct{ appVerifyOptions }
type KarabinerVerifyCmd struct{ appVerifyOptions }
type TerminalVerifyCmd struct{ appVerifyOptions }

func (c *NvimVerifyCmd) Run(rt *appctx.Runtime) error {
	return emitAppVerify(rt, "app.nvim.verify", "nvim", c.options())
}

func (c *LazygitVerifyCmd) Run(rt *appctx.Runtime) error {
	return emitAppVerify(rt, "app.lazygit.verify", "lazygit", c.options())
}

func (c *GhosttyVerifyCmd) Run(rt *appctx.Runtime) error {
	return emitAppVerify(rt, "app.ghostty.verify", "ghostty", c.options())
}

func (c *TmuxVerifyCmd) Run(rt *appctx.Runtime) error {
	return emitAppVerify(rt, "app.tmux.verify", "tmux", c.options())
}

func (c *KarabinerVerifyCmd) Run(rt *appctx.Runtime) error {
	return emitAppVerify(rt, "app.karabiner.verify", "karabiner", c.options())
}

func (c *TerminalVerifyCmd) Run(rt *appctx.Runtime) error {
	return emitAppVerify(rt, "app.terminal.verify", "terminal", c.options())
}

func emitAppVerify(rt *appctx.Runtime, command string, name string, opts appvalidator.Options) error {
	result := appvalidator.Verify(context.Background(), name, opts)
	summary := appvalidator.Summary(name, result)
	if !result.OK {
		return rt.Fail(command, false, summary, result, result.Diagnostics)
	}
	return rt.Emit(report.New(command, true, false, false, summary, result, result.Diagnostics))
}

func (c appVerifyOptions) options() appvalidator.Options {
	return appvalidator.Options{PublicRepoDir: c.PublicRepo}
}
