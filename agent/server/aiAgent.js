const OpenAI = require('openai');
const client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });

// Very simple chat wrapper. For production, maintain conversation state.
async function askAI(userText, conversationId = null) {
  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const resp = await client.chat.completions.create({
    model,
    messages: [
      { role: 'system', content: 'You are LiveKit AI assistant. Keep answers concise and helpful.' },
      { role: 'user', content: userText }
    ],
    max_tokens: 350
  });
  const txt = resp.choices?.[0]?.message?.content || resp.choices?.[0]?.text || '';
  return txt.trim();
}

module.exports = { askAI };
