const ipInput = document.getElementById('ip');
const portInput = document.getElementById('port');
const passwordInput = document.getElementById('password');
const connectBtn = document.getElementById('connect-btn');
const statusEl = document.getElementById('status');
const setupScreen = document.getElementById('setup-screen');
const remoteScreen = document.getElementById('remote-screen');
const remoteInfo = document.getElementById('remote-info');
const disconnectBtn = document.getElementById('disconnect-btn');
const canvas = document.getElementById('remote-canvas');
const ctx = canvas.getContext('2d');

let lastMouseSend = 0;
const MOUSE_THROTTLE_MS = 25;

connectBtn.addEventListener('click', async () => {
  const ip = ipInput.value.trim();
  const port = parseInt(portInput.value, 10) || 5900;
  const password = passwordInput.value.trim();
  if (!ip || !password) {
    statusEl.textContent = 'IP va parolni kiriting';
    statusEl.className = 'status err';
    return;
  }

  statusEl.textContent = 'Ulanmoqda...';
  statusEl.className = 'status';
  connectBtn.disabled = true;

  const res = await window.api.connectViewer({ ip, port, password });
  connectBtn.disabled = false;

  if (!res.success) {
    statusEl.textContent = 'Xato: ' + res.error;
    statusEl.className = 'status err';
    return;
  }

  remoteInfo.textContent = `${ip}:${port} bilan ulanildi`;
  setupScreen.style.display = 'none';
  remoteScreen.style.display = 'flex';
});

disconnectBtn.addEventListener('click', async () => {
  await window.api.disconnectViewer();
  backToSetup();
});

window.api.onConnectionClosed(() => {
  backToSetup();
});

function backToSetup() {
  remoteScreen.style.display = 'none';
  setupScreen.style.display = 'flex';
  statusEl.textContent = 'Ulanish uzildi';
  statusEl.className = 'status err';
}

window.api.onFrame(async (data) => {
  try {
    const blob = new Blob([data], { type: 'image/jpeg' });
    const bitmap = await createImageBitmap(blob);
    if (canvas.width !== bitmap.width) canvas.width = bitmap.width;
    if (canvas.height !== bitmap.height) canvas.height = bitmap.height;
    ctx.drawImage(bitmap, 0, 0);
    bitmap.close();
  } catch (err) {
    // ignore malformed/partial frame
  }
});

function normalizedPos(e) {
  const rect = canvas.getBoundingClientRect();
  const x = Math.min(Math.max((e.clientX - rect.left) / rect.width, 0), 1);
  const y = Math.min(Math.max((e.clientY - rect.top) / rect.height, 0), 1);
  return { x, y };
}

function buttonName(e) {
  if (e.button === 2) return 'right';
  if (e.button === 1) return 'middle';
  return 'left';
}

canvas.addEventListener('mousemove', (e) => {
  const now = Date.now();
  if (now - lastMouseSend < MOUSE_THROTTLE_MS) return;
  lastMouseSend = now;
  const { x, y } = normalizedPos(e);
  window.api.sendMouseEvent({ type: 'mouse-move', x, y });
});

canvas.addEventListener('mousedown', (e) => {
  e.preventDefault();
  const { x, y } = normalizedPos(e);
  window.api.sendMouseEvent({ type: 'mouse-down', x, y, button: buttonName(e) });
});

canvas.addEventListener('mouseup', (e) => {
  e.preventDefault();
  window.api.sendMouseEvent({ type: 'mouse-up', button: buttonName(e) });
});

canvas.addEventListener('contextmenu', (e) => e.preventDefault());

canvas.addEventListener(
  'wheel',
  (e) => {
    e.preventDefault();
    window.api.sendMouseEvent({ type: 'mouse-scroll', dx: e.deltaX, dy: e.deltaY });
  },
  { passive: false }
);
