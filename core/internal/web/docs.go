package web

import (
	"bytes"
	"embed"
	"strings"

	"github.com/yuin/goldmark"
	"github.com/yuin/goldmark/extension"
	"github.com/yuin/goldmark/renderer/html"
)

//go:embed ui/docs
var docsFS embed.FS

// DocNavSection groups related doc pages in the sidebar.
type DocNavSection struct {
	Label string
	Pages []DocNavPage
}

// DocNavPage represents a single entry in the docs sidebar.
type DocNavPage struct {
	Slug  string
	Label string
}

// DocNav is the ordered sidebar navigation, used in both the handler and templ.
var DocNav = []DocNavSection{
	{
		Label: "Getting Started",
		Pages: []DocNavPage{
			{Slug: "getting-started/quickstart", Label: "Quickstart"},
			{Slug: "getting-started/installation", Label: "Installation"},
		},
	},
	{
		Label: "Languages",
		Pages: []DocNavPage{
			{Slug: "languages/go", Label: "Go"},
			{Slug: "languages/rust", Label: "Rust"},
		},
	},
	{
		Label: "Platform",
		Pages: []DocNavPage{
			{Slug: "deployments", Label: "Deployments"},
			{Slug: "secrets", Label: "Secrets"},
			{Slug: "cli", Label: "CLI Reference"},
		},
	},
}

var md = goldmark.New(
	goldmark.WithExtensions(
		extension.GFM,
		extension.Table,
	),
	goldmark.WithRendererOptions(
		html.WithUnsafe(),
	),
)

// renderDoc loads a markdown file by slug and returns rendered HTML.
func renderDoc(slug string) (string, error) {
	data, err := docsFS.ReadFile("ui/docs/" + slug + ".md")
	if err != nil {
		return "", err
	}

	// Strip YAML frontmatter if present
	content := string(data)
	if strings.HasPrefix(content, "---") {
		if idx := strings.Index(content[3:], "---"); idx >= 0 {
			content = strings.TrimSpace(content[3+idx+3:])
		}
	}

	var buf bytes.Buffer
	if err := md.Convert([]byte(content), &buf); err != nil {
		return "", err
	}
	return buf.String(), nil
}

// docTitle returns the display title for a given slug from DocNav.
func docTitle(slug string) string {
	for _, section := range DocNav {
		for _, page := range section.Pages {
			if page.Slug == slug {
				return page.Label
			}
		}
	}
	return slug
}
