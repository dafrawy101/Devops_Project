(async () => {
  const joinBtn = document.getElementById('join');
  const roomInput = document.getElementById('room');
  const idInput = document.getElementById('identity');
  const chatEl = document.getElementById('chat');
  const messageEl = document.getElementById('message');
  const sendBtn = document.getElementById('send');
  const speakBtn = document.getElementById('speak');

  async function append(msg) {
    const d = document.createElement('div'); d.innerText = msg; chatEl.appendChild(d); chatEl.scrollTop = chatEl.scrollHeight;
  }

  joinBtn.onclick = async () => {
    const room = roomInput.value;
    const identity = idInput.value;
    const resp = await fetch('/token', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ room, identity }) });
    const { token } = await resp.json();
    if (!token) return append('Failed to get token');

    const script = document.createElement('script');
    script.src = 'https://unpkg.com/livekit-client/dist/livekit-client.umd.js';
    document.head.appendChild(script);
    script.onload = async () => {
      const { connect } = window.livekitClient;
      const roomObj = await connect(window.location.origin, token, { autoSubscribe: true });
      append('Connected to LiveKit room');

      const local = roomObj.localParticipant;
      try {
        const t = await local.createLocalVideoTrack();
        const v = document.getElementById('localVideo');
        v.srcObject = new MediaStream([t.mediaStreamTrack]);
      } catch (e) {}

      roomObj.on('participantConnected', p => append('Participant connected: ' + p.identity));
      roomObj.on('trackSubscribed', (track, publication, participant) => {
        if (track.kind === 'video') {
          const v = document.getElementById('remoteVideo');
          v.srcObject = new MediaStream([track.mediaStreamTrack]);
        }
      });
    };
  };

  sendBtn.onclick = async () => {
    const text = messageEl.value.trim();
    if (!text) return;
    append('You: ' + text);
    const r = await fetch('/ai/respond', { method: 'POST', headers: {'Content-Type':'application/json'}, body: JSON.stringify({ text }) });
    const j = await r.json();
    append('AI: ' + (j.text || '(no reply)'));
    const u = new SpeechSynthesisUtterance(j.text || '');
    speechSynthesis.speak(u);
    messageEl.value = '';
  };

  speakBtn.onclick = async () => {
    if (!('webkitSpeechRecognition' in window) && !('SpeechRecognition' in window)) {
      return append('Speech recognition not available in this browser.');
    }
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    const rec = new SpeechRecognition();
    rec.lang = 'en-US';
    rec.onresult = async (ev) => {
      const txt = ev.results[0][0].transcript;
      messageEl.value = txt;
      append('ASR: ' + txt);
    };
    rec.onerror = (e)=> append('ASR error: '+e.message);
    rec.start();
  };
})();
