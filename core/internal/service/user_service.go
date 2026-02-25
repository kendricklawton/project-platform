package service

import (
	"context"

	"connectrpc.com/connect"
	"github.com/kendricklawton/project-platform/core/internal/authctx"
	"github.com/kendricklawton/project-platform/core/internal/db"
	pb "github.com/kendricklawton/project-platform/gen/go/platform/v1"
)

type UserServer struct {
	Store db.Store
}

func (s *UserServer) GetMe(
	ctx context.Context,
	req *connect.Request[pb.GetMeRequest],
) (*connect.Response[pb.GetMeResponse], error) {

	// Extract UserID from context (injected by your AuthMiddleware)
	userID, ok := authctx.GetUserID(ctx)
	if !ok {
		// The context didn't have a UUID! Kick them out.
		return nil, connect.NewError(connect.CodeUnauthenticated, nil)
	}

	user, err := s.Store.GetUser(ctx, userID)
	if err != nil {
		return nil, connect.NewError(connect.CodeNotFound, err)
	}

	return connect.NewResponse(&pb.GetMeResponse{
		User: &pb.User{
			Id:    user.ID.String(),
			Email: user.Email,
			Name:  user.Name,
		},
	}), nil
}
