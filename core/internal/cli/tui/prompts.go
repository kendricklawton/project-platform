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

// PromptNewProject asks the user for details to scaffold a project
func PromptNewProject() (name string, framework string, err error) {
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
				Title("Framework").
				Options(
					huh.NewOption("Next.js", "nextjs"),
					huh.NewOption("Go API", "go"),
					huh.NewOption("Remix", "remix"),
					huh.NewOption("Docker (Dockerfile)", "docker"),
					huh.NewOption("Static HTML", "static"),
				).
				Value(&framework),
		),
	).WithTheme(customTheme())

	err = form.Run()
	return name, framework, err
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
