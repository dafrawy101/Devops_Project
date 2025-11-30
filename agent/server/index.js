require('dotenv').config();
const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const path = require('path');
const multer = require('multer');
const fs = require('fs');
const axios = require('axios');
const FormData = require('form-data');
const upload = multer({ dest: 'uploads/' });

const { createTokenForRoom } = require('./livekitClient');
const { askAI } = require('./aiAgent');
const db = require('./db');

const app = express();
app.use(cors());
app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, '..', 'frontend')));

const PORT = process.env.PORT || 3000;

// Health
app.get('/health', (req, res) => res.json({ ok: true }));

// Create/issue LiveKit token for a user to join a room
app.post('/token', async (req, res) => {
  try {
    const { room, identity } = req.body;
    const token = await createTokenForRoom(room || 'ai-room', identity || `user-${Date.now()}`);
    res.json({ token });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'failed to create token' });
  }
});

// Simple AI endpoint (text in -> text out)
app.post('/ai/respond', async (req, res) => {
  try {
    const { text, conversationId } = req.body;
    const aiResp = await askAI(text, conversationId);
    // log
    await db.logMessage({ conversation_id: conversationId || null, role: 'user', content: text });
    await db.logMessage({ conversation_id: conversationId || null, role: 'assistant', content: aiResp });
    res.json({ text: aiResp });
  } catch (err) {
    console.error('AI respond error', err);
    res.status(500).json({ error: 'ai error' });
  }
});

// Upload audio snippets endpoint: saves file, forwards to Whisper (OpenAI transcription)
app.post('/audio/upload', upload.single('audio'), async (req, res) => {
  try {
    const file = req.file;
    if (!file) return res.status(400).json({ error: 'no file' });

    // Prepare multipart/form-data to send to OpenAI transcription endpoint
    const form = new FormData();
    form.append('file', fs.createReadStream(file.path));
    form.append('model', 'whisper-1');
    // optionally append 'language' or other params

    const openaiKey = process.env.OPENAI_API_KEY;
    const resp = await axios.post('https://api.openai.com/v1/audio/transcriptions', form, {
      headers: {
        ...form.getHeaders(),
        Authorization: `Bearer ${openaiKey}`
      },
      maxBodyLength: Infinity
    });

    // cleanup uploaded file
    fs.unlinkSync(file.path);

    const transcript = resp.data.text;
    res.json({ transcript });
  } catch (err) {
    console.error('transcription error', err?.response?.data || err.message);
    res.status(500).json({ error: 'transcription error', detail: err?.response?.data || err.message });
  }
});

// LiveKit recording webhook endpoint
// LiveKit can be configured to POST recording metadata to this endpoint
app.post('/webhook/livekit-recording', async (req, res) => {
  try {
    // Example payload (from LiveKit): { name: 'recording-name', url: 'https://...' }
    const payload = req.body;
    console.log('livekit webhook payload', payload);

    const recordingUrl = payload.url || payload.recording_url || payload.download_url;
    if (!recordingUrl) {
      return res.status(400).json({ error: 'no recording url in payload' });
    }

    // Download the recording file to recordings/ directory
    const recordingsDir = path.join(__dirname, '..', 'recordings');
    if (!fs.existsSync(recordingsDir)) fs.mkdirSync(recordingsDir, { recursive: true });
    const outPath = path.join(recordingsDir, `recording-${Date.now()}.mp3`);

    const writer = fs.createWriteStream(outPath);
    const response = await axios.get(recordingUrl, { responseType: 'stream' });
    response.data.pipe(writer);
    await new Promise((resolve, reject) => {
      writer.on('finish', resolve);
      writer.on('error', reject);
    });

    // Now call Whisper transcription on downloaded file (reuse /audio/upload logic conceptually)
    const form = new FormData();
    form.append('file', fs.createReadStream(outPath));
    form.append('model', 'whisper-1');
    const openaiKey = process.env.OPENAI_API_KEY;
    const tResp = await axios.post('https://api.openai.com/v1/audio/transcriptions', form, {
      headers: {
        ...form.getHeaders(),
        Authorization: `Bearer ${openaiKey}`
      },
      maxBodyLength: Infinity
    });

    const transcript = tResp.data.text;
    console.log('transcript', transcript);

    // Optionally: pass transcript to AI for summary or action
    const aiSummary = await askAI('Summarize this recording:\n' + transcript);

    // Optionally log to DB
    await db.logMessage({ conversation_id: null, role: 'system', content: `Recording processed: ${payload.name || 'unnamed'}` });
    await db.logMessage({ conversation_id: null, role: 'assistant', content: aiSummary });

    res.json({ ok: true, transcript, aiSummary });
  } catch (err) {
    console.error('webhook processing error', err?.response?.data || err.message);
    res.status(500).json({ error: 'webhook processing error', detail: err?.response?.data || err.message });
  }
});

app.listen(PORT, () => console.log(`Server listening on ${PORT}`));
