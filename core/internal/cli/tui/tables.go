package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/lipgloss/table"
)

// ServiceRow holds display data for a deployed service.
type ServiceRow struct {
	Name     string
	Lang     string
	Status   string
	Revision string
	URL      string
}

// RevisionRow holds display data for a deployment revision.
type RevisionRow struct {
	ID        string
	Status    string
	CreatedAt string
	Message   string
}

// RenderServicesTable prints a minimalist services table.
func RenderServicesTable(services []ServiceRow) {
	t := table.New().
		Border(lipgloss.HiddenBorder()).
		BorderStyle(lipgloss.NewStyle().Foreground(ColorMuted)).
		Headers("SERVICE", "LANG", "STATUS", "REVISION", "URL").
		StyleFunc(func(row, col int) lipgloss.Style {
			if row == 0 {
				return BoldStyle.Padding(0, 2)
			}
			if col == 2 {
				switch services[row-1].Status {
				case "running":
					return lipgloss.NewStyle().Foreground(ColorGood).Padding(0, 2)
				case "error", "failed":
					return lipgloss.NewStyle().Foreground(ColorBad).Padding(0, 2)
				}
			}
			return BaseStyle.Padding(0, 2)
		})

	for _, s := range services {
		t.Row(s.Name, s.Lang, s.Status, s.Revision, s.URL)
	}
	fmt.Println(t.Render())
}

// RenderRevisionsTable prints a minimalist revisions table.
func RenderRevisionsTable(revisions []RevisionRow) {
	t := table.New().
		Border(lipgloss.HiddenBorder()).
		BorderStyle(lipgloss.NewStyle().Foreground(ColorMuted)).
		Headers("REVISION", "STATUS", "DEPLOYED", "MESSAGE").
		StyleFunc(func(row, col int) lipgloss.Style {
			if row == 0 {
				return BoldStyle.Padding(0, 2)
			}
			if col == 1 {
				switch revisions[row-1].Status {
				case "success":
					return lipgloss.NewStyle().Foreground(ColorGood).Padding(0, 2)
				case "failed":
					return lipgloss.NewStyle().Foreground(ColorBad).Padding(0, 2)
				}
			}
			return BaseStyle.Padding(0, 2)
		})

	for _, r := range revisions {
		t.Row(r.ID, r.Status, r.CreatedAt, r.Message)
	}
	fmt.Println(t.Render())
}
