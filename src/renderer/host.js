const sourceSelect = document.getElementById('source-select');
const portInput = document.getElementById('port');
const passwordInput = document.getElementById('password');
const startBtn = document.getElementById('start-btn');
const stopBtn = document.getElementById('stop-btn');
const statusEl = document.getElementById('status');
const macWarning = document.getElementById('mac-warning');
const setupCard = document.getElementById('setup-card');
const runningCard = document.getElementById('running-card');
const ipList = document.getElementById('ip-list');
const pinDisplay = document.getElementById('pin-display');
const connStatus = document.getElementById('conn-status');

let video = document.createElement('video');
video.autoplay = true;
video.muted = true;
let captureCanvas = document.createElement('canvas');
let captureCtx = captureCanvas.getContext('2d');
let intervalId = null;
let stream = null;

function randomPin() {
  return String(Math.floor(100000 + Math.random() * 900000));
}
passwordInput.value = randomPin();

async function loadSources() {
  const sources = await window.api.getScreenSources();
  sourceSelect.innerHTML = '';
  sources.forEach((s) => {
    const opt = document.createElement('option');
    opt.value = s.id;
    opt.textContent = s.name;
    sourceSelect.appendChild(opt);
  });
}

async function checkMac() {
  const perms = await window.api.checkMacPermissions();
  if (perms.screen !== 'granted' || perms.accessibility !== 'granted') {
    macWarning.style.display = 'block';
    macWarning.textContent =
      "macOS: Ekran yozish va Accessibility ruxsatlarini bering (Tizim sozlamalari > Maxfiylik va xavfsizlik), so'ng ilovani qayta ishga tushiring.";
  }
}

async function showIps() {
  const ips = await window.api.getLocalIps();
  ipList.innerHTML = ips.length
    ? ips.map((ip) => `<b>${ip}</b>`).join(', ') + ' manzillaridan biri'
    : 'IP manzil topilmadi';
}

async function startCapture(sourceId) {
  stream = await navigator.mediaDevices.getUserMedia({
    audio: false,
    video: {
      mandatory: {
        chromeMediaSource: 'desktop',
        chromeMediaSourceId: sourceId,
      },
    },
  });
  video.srcObject = stream;
  await video.play();

  captureCanvas.width = video.videoWidth || 1280;
  captureCanvas.height = video.videoHeight || 720;

  const fps = 8;
  intervalId = setInterval(() => {
    if (!video.videoWidth) return;
    if (captureCanvas.width !== video.videoWidth) captureCanvas.width = video.videoWidth;
    if (captureCanvas.height !== video.videoHeight) captureCanvas.height = video.videoHeight;
    captureCtx.drawImage(video, 0, 0, captureCanvas.width, captureCanvas.height);
    captureCanvas.toBlob(
      (blob) => {
        if (!blob) return;
        blob.arrayBuffer().then((buf) => window.api.sendFrame(buf));
      },
      'image/jpeg',
      0.5
    );
  }, 1000 / fps);
}

function stopCapture() {
  if (intervalId) clearInterval(intervalId);
  intervalId = null;
  if (stream) {
    stream.getTracks().forEach((t) => t.stop());
    stream = null;
  }
}

startBtn.addEventListener('click', async () => {
  const port = parseInt(portInput.value, 10) || 5900;
  const password = passwordInput.value.trim();
  const sourceId = sourceSelect.value;
  if (!password) {
    statusEl.textContent = 'Parol kiriting';
    statusEl.className = 'status err';
    return;
  }
  if (!sourceId) {
    statusEl.textContent = 'Ekran topilmadi';
    statusEl.className = 'status err';
    return;
  }

  statusEl.textContent = 'Ishga tushirilmoqda...';
  statusEl.className = 'status';

  const res = await window.api.startHost({ port, password });
  if (!res.success) {
    statusEl.textContent = 'Xato: ' + res.error;
    statusEl.className = 'status err';
    return;
  }

  try {
    await startCapture(sourceId);
  } catch (err) {
    statusEl.textContent = 'Ekranni olishda xato: ' + err.message;
    statusEl.className = 'status err';
    await window.api.stopHost();
    return;
  }

  pinDisplay.textContent = password;
  await showIps();
  setupCard.style.display = 'none';
  runningCard.style.display = 'block';
});

stopBtn.addEventListener('click', async () => {
  stopCapture();
  await window.api.stopHost();
  setupCard.style.display = 'block';
  runningCard.style.display = 'none';
  statusEl.textContent = '';
});

window.api.onViewerConnected(() => {
  connStatus.textContent = "Ulandi — masofaviy foydalanuvchi sichqonchani boshqarmoqda";
  connStatus.className = 'status ok';
});

window.api.onViewerDisconnected(() => {
  connStatus.textContent = 'Ulanish kutilmoqda...';
  connStatus.className = 'status';
});

window.api.onHostServerError((msg) => {
  statusEl.textContent = 'Server xatosi: ' + msg;
  statusEl.className = 'status err';
});

loadSources();
checkMac();
showIps();
