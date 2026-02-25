package service

import (
	"context"
	"fmt"
	"strings"

	"connectrpc.com/connect"
	"github.com/google/uuid"
	"github.com/kendricklawton/project-platform/core/internal/authctx"
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

	// Extract the actual authenticated user from the context
	creatorID, ok := authctx.GetUserID(ctx)
	if !ok {
		return nil, connect.NewError(connect.CodeUnauthenticated, fmt.Errorf("missing user identity"))
	}

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
		// If it's a known Postgres unique constraint error (SQLSTATE 23505)
		if strings.Contains(err.Error(), "SQLSTATE 23505") {
			return nil, connect.NewError(connect.CodeAlreadyExists, fmt.Errorf("team slug '%s' is already taken", req.Msg.Slug))
		}
		// Otherwise, it's a real 500 error
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to create team: %w", err))
	}

	return connect.NewResponse(&pb.CreateTeamResponse{
		Id:   team.ID.String(),
		Name: team.Name,
		Slug: team.Slug,
	}), nil
}
