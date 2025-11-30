# LiveKit AI Agent — Full Advanced (Version C)

This is the full advanced project scaffold with:
- Node.js backend (Express)
- LiveKit token issuance
- OpenAI chat (GPT) wrapper
- Server-side Whisper transcription endpoint (/audio/upload)
- LiveKit recording webhook endpoint (/webhook/livekit-recording)
- Simple frontend to join LiveKit room and chat with AI
- Postgres schema and basic logging
- Docker + docker-compose for local dev

## How to run (development)
1. Copy `.env.example` to `.env` and fill values (OpenAI key, LiveKit keys, DATABASE_URL).
2. Install deps: `npm install`
3. Create DB tables: run `psql $DATABASE_URL -f db/schema.sql` or use a DB client.
4. Start server: `npm run dev` (requires `nodemon`) or `npm start`.
5. Open `http://localhost:3000` and test.

## Notes about the new endpoints
- `/audio/upload` accepts a multipart/form-data `audio` file and forwards to OpenAI's transcription API (Whisper).
  It returns `{ transcript }` in the response.
- `/webhook/livekit-recording` is a webhook endpoint that LiveKit can POST to when a recording is ready.
  It expects JSON with a `name` and `url` (pointing to the recording). The endpoint downloads the file,
  saves it to `recordings/`, then calls the transcription flow and optionally sends the transcript to the AI.

Make sure your server is reachable (public URL) for LiveKit to post webhooks - use ngrok or a deployed URL in production.
