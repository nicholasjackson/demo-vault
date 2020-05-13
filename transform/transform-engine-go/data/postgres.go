package data

import (
	"database/sql"
	"fmt"
	"time"

	"github.com/jmoiron/sqlx"
	"github.com/lib/pq"
)

// Order defines an order object which is stored in the DB orders table
type Order struct {
	ID         int            `db:"id" json:"id"`
	CardNumber string         `db:"card_number" json:"card_number"`
	CreatedAt  string         `db:"created_at" json:"-"`
	UpdatedAt  string         `db:"updated_at" json:"-"`
	DeletedAt  sql.NullString `db:"deleted_at" json:"-"`
}

// PostgreSQL is a database client for PostgresSQL
type PostgreSQL struct {
	db *sqlx.DB
}

// NewPostgreSQLClient creates a new SQL client
func NewPostgreSQLClient(connection string) (*PostgreSQL, error) {
	db, err := sqlx.Connect("postgres", connection)
	if err != nil {
		return nil, err
	}

	ps := &PostgreSQL{db}
	_, err = ps.IsConnected()

	if err != nil {
		return nil, err
	}

	return ps, nil
}

// IsConnected checks the connection to the database and returns an error if not connected
func (c *PostgreSQL) IsConnected() (bool, error) {
	err := c.db.Ping()
	if err != nil {
		return false, err
	}

	return true, nil
}

// SaveOrder saves the order into the datbase
func (c *PostgreSQL) SaveOrder(o Order) (int64, error) {
	var id int64

	err := c.db.QueryRow(
		`INSERT INTO orders (card_number, created_at, updated_at) VALUES ($1, $2, $3) RETURNING id`,
		o.CardNumber,
		pq.FormatTimestamp(time.Now()),
		pq.FormatTimestamp(time.Now()),
	).Scan(&id)

	if err != nil {
		return -1, fmt.Errorf("Unable to insert record into DB. Error: %s", err)
	}

	fmt.Println("id", id)

	return id, nil
}
