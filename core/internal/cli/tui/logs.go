package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
)

var (
	stdoutStyle = lipgloss.NewStyle().Foreground(ColorMuted)
	stderrStyle = lipgloss.NewStyle().Foreground(ColorBad)
	systemStyle = lipgloss.NewStyle().Foreground(ColorAccent).Italic(true)
)

// StreamLog formats and prints a single line of log output
func StreamLog(stream string, content string) {
	switch stream {
	case "stderr":
		fmt.Println(stderrStyle.Render(content))
	case "system":
		fmt.Println(systemStyle.Render("SYSTEM: " + content))
	default:
		// Default to stdout
		fmt.Println(stdoutStyle.Render(content))
	}
}
