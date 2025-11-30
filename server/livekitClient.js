// Helper to create ephemeral tokens using LiveKit server-side SDK or manual JWT
const { AccessToken } = require('livekit-server-sdk');

const API_KEY = process.env.LIVEKIT_API_KEY;
const API_SECRET = process.env.LIVEKIT_API_SECRET;

if (!API_KEY || !API_SECRET) console.warn('LIVEKIT_API_KEY/SECRET not set in .env');

async function createTokenForRoom(roomName, identity) {
  const at = new AccessToken(API_KEY, API_SECRET, { identity });
  at.addGrant({ room: roomName });
  at.metadata = JSON.stringify({ user: identity });
  return at.toJwt();
}

module.exports = { createTokenForRoom };
