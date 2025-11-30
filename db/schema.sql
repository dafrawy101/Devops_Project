CREATE TABLE IF NOT EXISTS conversations (
  id SERIAL PRIMARY KEY,
  title TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages (
  id SERIAL PRIMARY KEY,
  conversation_id INTEGER REFERENCES conversations(id) ON DELETE SET NULL,
  role TEXT,
  content TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
