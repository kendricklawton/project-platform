package store

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/workos/workos-go/v6/pkg/usermanagement"
)

// MemoryStore defines the interface for temporary session storage.
type MemoryStore interface {
	Save(ctx context.Context, key string, val usermanagement.AuthenticateResponse) error
	Get(ctx context.Context, key string) (*usermanagement.AuthenticateResponse, error)
	Delete(ctx context.Context, key string) error
}

// RedisStore implements MemoryStore using a distributed Redis instance.
type RedisStore struct {
	client *redis.Client
	ttl    time.Duration
}

func NewRedisStore(url string) (*RedisStore, error) {
	opt, err := redis.ParseURL(url)
	if err != nil {
		return nil, fmt.Errorf("failed to parse redis url: %w", err)
	}
	return &RedisStore{
		client: redis.NewClient(opt),
		ttl:    5 * time.Minute,
	}, nil
}

func (s *RedisStore) Save(ctx context.Context, key string, val usermanagement.AuthenticateResponse) error {
	data, err := json.Marshal(val)
	if err != nil {
		return err
	}
	return s.client.Set(ctx, "Memory:"+key, data, s.ttl).Err()
}

func (s *RedisStore) Get(ctx context.Context, key string) (*usermanagement.AuthenticateResponse, error) {
	data, err := s.client.Get(ctx, "Memory:"+key).Bytes()
	if err != nil {
		return nil, err
	}
	var res usermanagement.AuthenticateResponse
	if err := json.Unmarshal(data, &res); err != nil {
		return nil, err
	}
	return &res, nil
}

func (s *RedisStore) Delete(ctx context.Context, key string) error {
	return s.client.Del(ctx, "Memory:"+key).Err()
}

// LocalStore implements MemoryStore using local RAM for development.
type LocalStore struct {
	data map[string]usermanagement.AuthenticateResponse
}

func NewLocalStore() *LocalStore {
	return &LocalStore{data: make(map[string]usermanagement.AuthenticateResponse)}
}

func (s *LocalStore) Save(ctx context.Context, key string, val usermanagement.AuthenticateResponse) error {
	s.data[key] = val
	return nil
}

func (s *LocalStore) Get(ctx context.Context, key string) (*usermanagement.AuthenticateResponse, error) {
	val, ok := s.data[key]
	if !ok {
		return nil, fmt.Errorf("Memory code not found")
	}
	return &val, nil
}

func (s *LocalStore) Delete(ctx context.Context, key string) error {
	delete(s.data, key)
	return nil
}
