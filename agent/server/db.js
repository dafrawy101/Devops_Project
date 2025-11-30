const { Pool } = require('pg');
const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function logMessage({ conversation_id = null, role, content }) {
  const q = 'INSERT INTO messages(conversation_id, role, content, created_at) VALUES($1,$2,$3,NOW())';
  try {
    await pool.query(q, [conversation_id, role, content]);
  } catch (err) {
    console.error('db log error', err.message);
  }
}

module.exports = { logMessage };
