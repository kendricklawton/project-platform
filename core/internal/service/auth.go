package service

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/kendricklawton/project-platform/core/internal/db"
)

type AuthService struct {
	Store db.Store
}

func NewAuthService(store db.Store) *AuthService {
	return &AuthService{Store: store}
}

type UserProfile struct {
	Email     string
	FirstName string
	LastName  string
}

func (s *AuthService) ProvisionUser(ctx context.Context, p UserProfile) (*db.User, error) {
	user, err := s.Store.GetUserByEmail(ctx, p.Email)
	if err == nil {
		return &user, nil
	}

	if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	userID, err := uuid.NewV7()
	if err != nil {
		return nil, fmt.Errorf("generating user ID: %w", err)
	}
	teamID, err := uuid.NewV7()
	if err != nil {
		return nil, fmt.Errorf("generating team ID: %w", err)
	}
	fullName := fmt.Sprintf("%s %s", p.FirstName, p.LastName)

	_, err = s.Store.OnboardUserWithTeam(ctx, db.OnboardUserWithTeamParams{
		ID:     userID,
		Email:  p.Email,
		Name:   fullName,
		ID_2:   teamID,
		Name_2: fmt.Sprintf("%s's Team", p.FirstName),
		Slug:   fmt.Sprintf("%s-team", generateSlug(fullName)),
	})
	if err != nil {
		return nil, fmt.Errorf("onboarding user: %w", err)
	}

	return &db.User{ID: userID, Email: p.Email, Name: fullName}, nil
}

func generateSlug(name string) string {
	reg := regexp.MustCompile("[^a-z0-9]+")
	return strings.Trim(reg.ReplaceAllString(strings.ToLower(name), "-"), "-")
}
