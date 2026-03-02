package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/kendricklawton/project-platform/core/internal/cli/tui"
	"github.com/spf13/cobra"
)

var initLang string

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Detect language and create plat.toml",
	Run: func(cmd *cobra.Command, args []string) {
		lang := initLang
		if lang == "" {
			lang = detectLang()
		}
		if lang == "" {
			tui.ShowError("Could not detect language. Use --lang go or --lang rust.")
			os.Exit(1)
		}
		if lang != "go" && lang != "rust" {
			tui.ShowError("Unsupported language. Use --lang go or --lang rust.")
			os.Exit(1)
		}
		writePlatToml(lang)
	},
}

func init() {
	initCmd.Flags().StringVar(&initLang, "lang", "", "Force language: go or rust")
	rootCmd.AddCommand(initCmd)
}

func detectLang() string {
	if _, err := os.Stat("go.mod"); err == nil {
		return "go"
	}
	if _, err := os.Stat("Cargo.toml"); err == nil {
		return "rust"
	}
	return ""
}

func writePlatToml(lang string) {
	if _, err := os.Stat("plat.toml"); err == nil {
		tui.ShowInfo("plat.toml already exists.")
		return
	}

	dir, _ := os.Getwd()
	name := filepath.Base(dir)

	var buildCmd, runCmd string
	switch lang {
	case "go":
		buildCmd = "go build -o bin/app ."
		runCmd = "./bin/app"
	case "rust":
		buildCmd = "cargo build --release"
		runCmd = "./target/release/" + name
	}

	content := fmt.Sprintf(`[app]
name = "%s"
lang = "%s"

[build]
command = "%s"

[run]
command = "%s"
`, name, lang, buildCmd, runCmd)

	if err := os.WriteFile("plat.toml", []byte(content), 0644); err != nil {
		tui.ShowError("Failed to write plat.toml: " + err.Error())
		os.Exit(1)
	}
	tui.ShowSuccess(fmt.Sprintf("Created plat.toml for %s project: %s", strings.ToUpper(lang), name))
}
