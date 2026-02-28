package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
)

var (
	// Minimalist monochrome palette
	ColorText   = lipgloss.Color("#EDEDED") // Off-white
	ColorMuted  = lipgloss.Color("#737373") // Grey
	ColorGood   = lipgloss.Color("#22C55E") // Subtle Green
	ColorBad    = lipgloss.Color("#EF4444") // Subtle Red
	ColorAccent = lipgloss.Color("#FFFFFF") // Bright White

	// Typography
	BaseStyle = lipgloss.NewStyle().Foreground(ColorText)
	DimStyle  = lipgloss.NewStyle().Foreground(ColorMuted)
	BoldStyle = lipgloss.NewStyle().Foreground(ColorAccent).Bold(true)

	// Status Indicators
	SuccessPrefix = lipgloss.NewStyle().Foreground(ColorGood).SetString("✔ ")
	ErrorPrefix   = lipgloss.NewStyle().Foreground(ColorBad).SetString("✖ ")
	InfoPrefix    = lipgloss.NewStyle().Foreground(ColorMuted).SetString("→ ")
)

// ShowSuccess prints a minimalist success message
func ShowSuccess(msg string) {
	fmt.Println(SuccessPrefix.Render() + BaseStyle.Render(msg))
}

// ShowError prints a minimalist error message
func ShowError(msg string) {
	fmt.Println(ErrorPrefix.Render() + BaseStyle.Render(msg))
}

// ShowInfo prints a muted informational message
func ShowInfo(msg string) {
	fmt.Println(InfoPrefix.Render() + DimStyle.Render(msg))
}
