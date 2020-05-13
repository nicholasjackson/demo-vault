CREATE TABLE orders (
    id SERIAL PRIMARY KEY, 
    card_number VARCHAR (255) NOT NULL,
    created_at TIMESTAMP NOT NULL, 
    updated_at TIMESTAMP NOT NULL, 
    deleted_at TIMESTAMP
);