package cmds

import (
	"fmt"

	"github.com/kendricklawton/project-platform/core/internal/cli"
	"github.com/spf13/cobra"
)

var teamsCmd = &cobra.Command{
	Use: "teams",
	// Aliases: []string{"team", "t"},
	Short: "Manage organization teams and members",
	Long:  "Manage organization teams and members",
}
var createCmd = &cobra.Command{
	Use:   "create [name]",
	Short: "Create a new team",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("🚀 Creating team: %s\n", args[0])
	},
}

// --- Member Management ---

// Parent command for members to keep the structure clean
var membersCmd = &cobra.Command{
	Use:   "members",
	Short: "Manage team membership and roles",
}

var listMembersCmd = &cobra.Command{
	Use:   "list [project-id]",
	Short: "List all members of a project",
	Args:  cobra.ExactArgs(1),
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("📋 Fetching members for project %s...\n", args[0])
		// Stub output based on your project_members table
		fmt.Println("USER_ID                              ROLE")
		fmt.Println("------------------------------------ --------")
		fmt.Println("user_01JG3BCPTRTSTTWQ...          admin")
	},
}

var editMemberCmd = &cobra.Command{
	Use:   "edit [project-id] [user-id] --role [role]",
	Short: "Update a member's role",
	Args:  cobra.ExactArgs(2),
	Run: func(cmd *cobra.Command, args []string) {
		role, _ := cmd.Flags().GetString("role")
		fmt.Printf("🔄 Updating user %s in project %s to role: %s\n", args[1], args[0], role)
	},
}

var deleteMemberCmd = &cobra.Command{
	Use:   "remove [project-id] [user-id]",
	Short: "Remove a member from a team",
	Args:  cobra.ExactArgs(2),
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("❌ Removing user %s from project %s\n", args[1], args[0])
	},
}

func init() {
	teamsCmd.AddCommand(listMembersCmd)
	teamsCmd.AddCommand(editMemberCmd)
	teamsCmd.AddCommand(deleteMemberCmd)
	cli.RootCmd.AddCommand(teamsCmd)
}
