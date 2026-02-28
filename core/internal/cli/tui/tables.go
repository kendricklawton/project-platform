package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/lipgloss/table"
)

// ProjectRow is a simple struct to hold data for the table
type ProjectRow struct {
	Name        string
	Framework   string
	Environment string
	Status      string
}

// RenderProjectsTable draws a minimalist table to the terminal
func RenderProjectsTable(projects []ProjectRow) {
	t := table.New().
		Border(lipgloss.HiddenBorder()).
		BorderStyle(lipgloss.NewStyle().Foreground(ColorMuted)).
		Headers("PROJECT", "FRAMEWORK", "ENV", "STATUS").
		StyleFunc(func(row, col int) lipgloss.Style {
			if row == 0 {
				return BoldStyle.Padding(0, 2)
			}
			// Color the status column
			if col == 3 {
				status := projects[row-1].Status
				if status == "ready" {
					return lipgloss.NewStyle().Foreground(ColorGood).Padding(0, 2)
				}
				if status == "error" {
					return lipgloss.NewStyle().Foreground(ColorBad).Padding(0, 2)
				}
			}
			return BaseStyle.Padding(0, 2)
		})

	for _, p := range projects {
		t.Row(p.Name, p.Framework, p.Environment, p.Status)
	}

	fmt.Println(t.Render())
}
