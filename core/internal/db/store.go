package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Store defines all functions to execute db queries and transactions.
type Store interface {
	Querier
	ExecTx(ctx context.Context, fn func(*Queries) error) error
	Close()
}

// SQLStore is the concrete implementation
type SQLStore struct {
	*Queries
	pool *pgxpool.Pool
}

// Connect initializes a high-performance connection pool using pgxpool.
// Note: pgxpool requires a context to establish the initial connections.
func Connect(ctx context.Context, databaseURL string) (Store, error) {
	// pgxpool automatically manages connection pooling and multiplexing
	pool, err := pgxpool.New(ctx, databaseURL)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	// Verify the database is actually reachable
	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("database unreachable: %w", err)
	}

	return &SQLStore{
		Queries: New(pool),
		pool:    pool,
	}, nil
}

// ExecTx handles the manual transaction lifecycle natively using pgx.Tx
func (s *SQLStore) ExecTx(ctx context.Context, fn func(*Queries) error) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}

	q := New(tx)
	err = fn(q)
	if err != nil {
		if rbErr := tx.Rollback(ctx); rbErr != nil {
			return fmt.Errorf("tx err: %v, rollback err: %v", err, rbErr)
		}
		return err
	}

	return tx.Commit(ctx)
}

// Close gracefully shuts down the database connection pool.
func (s *SQLStore) Close() {
	s.pool.Close()
}
