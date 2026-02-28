package service

import (
	"context"
	"errors"
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

func NewTeamServer(store db.Store) *TeamServer {
	return &TeamServer{Store: store}
}

func (s *TeamServer) CreateTeam(
	ctx context.Context,
	req *connect.Request[pb.CreateTeamRequest],
) (*connect.Response[pb.CreateTeamResponse], error) {

	teamID, err := uuid.NewV7()
	if err != nil {
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	creatorID, ok := authctx.GetUserID(ctx)
	if !ok {
		return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("missing user identity"))
	}

	team, err := s.Store.CreateTeamWithOwner(ctx, db.CreateTeamWithOwnerParams{
		ID:     teamID,
		Name:   req.Msg.Name,
		Slug:   req.Msg.Slug,
		UserID: creatorID,
	})

	if err != nil {
		if strings.Contains(err.Error(), "23505") {
			return nil, connect.NewError(connect.CodeAlreadyExists, fmt.Errorf("team slug '%s' is already taken", req.Msg.Slug))
		}
		return nil, connect.NewError(connect.CodeInternal, fmt.Errorf("failed to create team: %w", err))
	}

	return connect.NewResponse(&pb.CreateTeamResponse{
		Id:   team.ID.String(),
		Name: team.Name,
		Slug: team.Slug,
	}), nil
}
