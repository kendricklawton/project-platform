package service

import (
	"context"
	"errors"

	"connectrpc.com/connect"
	"github.com/jackc/pgx/v5"
	"github.com/kendricklawton/project-platform/core/internal/authctx"
	"github.com/kendricklawton/project-platform/core/internal/db"
	pb "github.com/kendricklawton/project-platform/gen/go/platform/v1"
)

type UserServer struct {
	Store db.Store
}

func NewUserServer(store db.Store) *UserServer {
	return &UserServer{Store: store}
}

func (s *UserServer) GetMe(
	ctx context.Context,
	req *connect.Request[pb.GetMeRequest],
) (*connect.Response[pb.GetMeResponse], error) {

	userID, ok := authctx.GetUserID(ctx)
	if !ok {
		return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("missing user identity"))
	}

	user, err := s.Store.GetUser(ctx, userID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, connect.NewError(connect.CodeNotFound, errors.New("user not found"))
		}
		return nil, connect.NewError(connect.CodeInternal, err)
	}

	return connect.NewResponse(&pb.GetMeResponse{
		User: &pb.User{
			Id:    user.ID.String(),
			Email: user.Email,
			Name:  user.Name,
		},
	}), nil
}
