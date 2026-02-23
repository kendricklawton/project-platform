package service

import (
	"context"
	"fmt"

	"connectrpc.com/connect"
	"github.com/google/uuid"
	"github.com/kendricklawton/project-platform/core/internal/db"
	pb "github.com/kendricklawton/project-platform/gen/go/platform/v1"
)

type TeamServer struct {
	Store db.Store
}

func (s *TeamServer) CreateTeam(
	ctx context.Context,
	req *connect.Request[pb.CreateTeamRequest],
) (*connect.Response[pb.CreateTeamResponse], error) {

	teamID, err := uuid.NewV7()
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	// TODO: Replace with real auth context retrieval
	creatorID := uuid.MustParse("00000000-0000-0000-0000-000000000000")

	var team db.Team

	// Execute Atomically
	err = s.Store.ExecTx(ctx, func(q *db.Queries) error {
		var txErr error

		// Create the Team
		team, txErr = q.CreateTeam(ctx, db.CreateTeamParams{
			ID:   teamID,
			Name: req.Msg.Name,
			Slug: req.Msg.Slug,
		})
		if txErr != nil {
			return txErr
		}

		// Add the Creator as Owner
		return q.AddTeamMember(ctx, db.AddTeamMemberParams{
			TeamID: team.ID,
			UserID: creatorID,
			Role:   "owner",
		})
	})

	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to create team: %w", err))
	}

	return connect.NewResponse(&pb.CreateTeamResponse{
		Id:   team.ID.String(),
		Name: team.Name,
		Slug: team.Slug,
	}), nil
}
