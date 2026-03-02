package tui

import (
	"errors"

	"github.com/charmbracelet/huh"
)

// customTheme strips out heavy colors for a minimalist vibe
func customTheme() *huh.Theme {
	t := huh.ThemeBase()
	t.Focused.Base = t.Focused.Base.Foreground(ColorText)
	t.Focused.Title = t.Focused.Title.Foreground(ColorAccent).Bold(true)
	t.Focused.TextInput.Prompt = t.Focused.TextInput.Prompt.Foreground(ColorMuted)
	t.Focused.SelectedOption = t.Focused.SelectedOption.Foreground(ColorAccent).SetString("> ")
	t.Focused.UnselectedOption = t.Focused.UnselectedOption.Foreground(ColorMuted)
	return t
}

// PromptNewProject asks for a project name and language (Go or Rust only).
func PromptNewProject() (name string, lang string, err error) {
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Project Name").
				Value(&name).
				Validate(func(str string) error {
					if str == "" {
						return errors.New("project name is required")
					}
					return nil
				}),

			huh.NewSelect[string]().
				Title("Language").
				Options(
					huh.NewOption("Go", "go"),
					huh.NewOption("Rust", "rust"),
				).
				Value(&lang),
		),
	).WithTheme(customTheme())

	err = form.Run()
	return name, lang, err
}

// Confirm asks a simple Yes/No question
func Confirm(msg string) (bool, error) {
	var confirm bool
	err := huh.NewConfirm().
		Title(msg).
		Value(&confirm).
		WithTheme(customTheme()).
		Run()
	return confirm, err
}
