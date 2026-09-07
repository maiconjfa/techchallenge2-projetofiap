CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(64) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Seed de desenvolvimento: chave = "tm_key_dev"
INSERT INTO api_keys (name, key_hash)
VALUES ('dev-seed-key', 'e5e27b0f95327d112c9147fcbf107cd6f0269c68d08cab5ab335c23d0eaf578b')
ON CONFLICT (key_hash) DO NOTHING;