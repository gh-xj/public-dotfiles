package logx

import (
	"io"
	"log/slog"
	"os"

	"github.com/lmittmann/tint"
	"golang.org/x/term"
)

type Options struct {
	Verbose bool
	NoColor bool
	Writer  io.Writer
}

func Setup(opts Options) {
	w := opts.Writer
	if w == nil {
		w = os.Stderr
	}
	level := slog.LevelInfo
	if opts.Verbose {
		level = slog.LevelDebug
	}
	handler := tint.NewHandler(w, &tint.Options{
		Level:   level,
		NoColor: opts.NoColor || os.Getenv("NO_COLOR") != "" || !isTerminal(w),
		ReplaceAttr: func(_ []string, attr slog.Attr) slog.Attr {
			if attr.Key == slog.TimeKey {
				return slog.Attr{}
			}
			return attr
		},
	})
	slog.SetDefault(slog.New(handler))
}

func isTerminal(w io.Writer) bool {
	file, ok := w.(*os.File)
	if !ok {
		return false
	}
	return term.IsTerminal(int(file.Fd()))
}
