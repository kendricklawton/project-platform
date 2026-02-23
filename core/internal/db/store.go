package db

import (
	"context"
	"database/sql"
	"fmt"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// Store defines all functions to execute db queries and transactions.
type Store interface {
	Querier
	ExecTx(ctx context.Context, fn func(*Queries) error) error
	Close() error
}

// SQLStore is the concrete implementation
type SQLStore struct {
	*Queries
	db *sql.DB
}

func Connect(databaseURL string) (Store, error) {
	if databaseURL == "" {
		databaseURL = "postgres://platform:secretpassword@localhost:5432/platform_db?sslmode=disable"
	}

	conn, err := sql.Open("pgx", databaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to open database connection: %w", err)
	}

	if err := conn.Ping(); err != nil {
		return nil, fmt.Errorf("database unreachable: %w", err)
	}

	return &SQLStore{
		Queries: New(conn),
		db:      conn,
	}, nil
}

// ExecTx handles the manual transaction lifecycle
func (s *SQLStore) ExecTx(ctx context.Context, fn func(*Queries) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}

	q := New(tx)
	err = fn(q)
	if err != nil {
		if rbErr := tx.Rollback(); rbErr != nil {
			return fmt.Errorf("tx err: %v, rollback err: %v", err, rbErr)
		}
		return err
	}

	return tx.Commit()
}

// Close gracefully shuts down the database connection pool.
func (s *SQLStore) Close() error {
	return s.db.Close()
}
