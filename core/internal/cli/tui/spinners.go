package tui

import (
	"github.com/charmbracelet/huh/spinner"
)

// RunLoader executes a function while showing a minimalist spinner
func RunLoader(message string, action func()) error {
	return spinner.New().
		Type(spinner.Dots).
		Title(DimStyle.Render(message)).
		Action(action).
		Run()
}
