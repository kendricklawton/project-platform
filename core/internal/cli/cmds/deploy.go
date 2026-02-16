package cmds

import (
	"fmt"

	"github.com/kendricklawton/project-platform/core/internal/cli"
	"github.com/spf13/cobra"
)

var (
	prod     bool
	prebuilt bool
)

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Deploy your project to the platform",
	Long: `Deploys your project. By default, it creates a unique preview URL.
Use --prod to deploy to production or --prebuilt for CI/CD workflows.`,
	Run: func(cmd *cobra.Command, args []string) {
		if prebuilt {
			fmt.Println("📦 Prebuilt: Deploys the local build output (useful for CI/CD).")
			return
		}

		if prod {
			fmt.Println("🌐 Production: Deploys to your live production domain.")
			return
		}

		fmt.Println("🚀 Preview: Deploys your code and provides a unique preview URL.")
	},
}

func init() {
	deployCmd.Flags().BoolVar(&prod, "prod", false, "Deploy to your live production domain")
	deployCmd.Flags().BoolVar(&prebuilt, "prebuilt", false, "Deploy the local build output (useful for CI/CD)")

	cli.RootCmd.AddCommand(deployCmd)
}
