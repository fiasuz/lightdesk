const { app, BrowserWindow, ipcMain, desktopCapturer, screen, systemPreferences } = require('electron');
const path = require('path');
const os = require('os');
const WebSocket = require('ws');
const mouseControl = require('./mouseControl');

let mainWindow = null;

// --- Host-mode state (this machine is being controlled) ---
let wss = null;
let hostSocket = null; // the single authenticated viewer, if any
let hostPassword = null;
let mouseQueue = Promise.resolve();

// --- Viewer-mode state (this machine is controlling another one) ---
let wsClient = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 700,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  stopHostServer();
  if (wsClient) wsClient.close();
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

// ---------- Shared helpers ----------

ipcMain.handle('get-local-ips', () => {
  const nets = os.networkInterfaces();
  const ips = [];
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal) ips.push(net.address);
    }
  }
  return ips;
});

ipcMain.handle('get-screen-sources', async () => {
  const sources = await desktopCapturer.getSources({
    types: ['screen'],
    thumbnailSize: { width: 300, height: 180 },
  });
  return sources.map((s) => ({ id: s.id, name: s.name, thumbnail: s.thumbnail.toDataURL() }));
});

ipcMain.handle('check-mac-permissions', () => {
  if (process.platform !== 'darwin') return { screen: 'granted', accessibility: 'granted' };
  const screenStatus = systemPreferences.getMediaAccessStatus('screen');
  const accessibilityGranted = systemPreferences.isTrustedAccessibilityClient(false);
  return { screen: screenStatus, accessibility: accessibilityGranted ? 'granted' : 'denied' };
});

// ---------- Host mode ----------

function stopHostServer() {
  if (hostSocket) {
    try { hostSocket.close(); } catch (e) { /* ignore */ }
    hostSocket = null;
  }
  if (wss) {
    try { wss.close(); } catch (e) { /* ignore */ }
    wss = null;
  }
  hostPassword = null;
}

function enqueueMouseMsg(msg) {
  mouseQueue = mouseQueue.then(() => handleMouseMsg(msg)).catch((err) => console.error('mouse error', err));
}

async function handleMouseMsg(msg) {
  const { width, height } = screen.getPrimaryDisplay().size;
  const x = Math.min(Math.max(msg.x, 0), 1) * width;
  const y = Math.min(Math.max(msg.y, 0), 1) * height;
  switch (msg.type) {
    case 'mouse-move':
      await mouseControl.move(x, y);
      break;
    case 'mouse-down':
      await mouseControl.move(x, y);
      await mouseControl.down(msg.button);
      break;
    case 'mouse-up':
      await mouseControl.up(msg.button);
      break;
    case 'mouse-scroll':
      await mouseControl.scroll(msg.dx, msg.dy);
      break;
    default:
      break;
  }
}

ipcMain.handle('start-host', async (event, { port, password }) => {
  stopHostServer();
  hostPassword = password;

  try {
    wss = new WebSocket.Server({ port });
  } catch (err) {
    return { success: false, error: err.message };
  }

  wss.on('connection', (socket) => {
    if (hostSocket) {
      // Only one controller at a time, matching AnyDesk-lite scope.
      socket.close(1000, 'busy');
      return;
    }
    socket.authenticated = false;

    socket.on('message', (data, isBinary) => {
      if (isBinary) return;
      let msg;
      try { msg = JSON.parse(data.toString()); } catch (e) { return; }

      if (msg.type === 'auth') {
        if (msg.password === hostPassword) {
          socket.authenticated = true;
          hostSocket = socket;
          const { width, height } = screen.getPrimaryDisplay().size;
          socket.send(JSON.stringify({ type: 'auth-ok', width, height }));
          if (mainWindow) mainWindow.webContents.send('viewer-connected');
        } else {
          socket.send(JSON.stringify({ type: 'auth-fail' }));
          socket.close();
        }
        return;
      }

      if (!socket.authenticated) return;
      enqueueMouseMsg(msg);
    });

    socket.on('close', () => {
      if (hostSocket === socket) {
        hostSocket = null;
        if (mainWindow) mainWindow.webContents.send('viewer-disconnected');
      }
    });
  });

  wss.on('error', (err) => {
    if (mainWindow) mainWindow.webContents.send('host-server-error', err.message);
  });

  return { success: true };
});

ipcMain.handle('stop-host', () => {
  stopHostServer();
  return { success: true };
});

ipcMain.on('host-frame', (event, buffer) => {
  if (hostSocket && hostSocket.readyState === WebSocket.OPEN) {
    hostSocket.send(Buffer.from(buffer));
  }
});

// ---------- Viewer mode ----------

ipcMain.handle('connect-viewer', (event, { ip, port, password }) => {
  return new Promise((resolve) => {
    let settled = false;
    let client;
    try {
      client = new WebSocket(`ws://${ip}:${port}`);
    } catch (err) {
      resolve({ success: false, error: err.message });
      return;
    }
    wsClient = client;

    client.on('open', () => {
      client.send(JSON.stringify({ type: 'auth', password }));
    });

    client.on('message', (data, isBinary) => {
      if (isBinary) {
        if (mainWindow) mainWindow.webContents.send('frame', data);
        return;
      }
      let msg;
      try { msg = JSON.parse(data.toString()); } catch (e) { return; }
      if (msg.type === 'auth-ok') {
        settled = true;
        resolve({ success: true, width: msg.width, height: msg.height });
      } else if (msg.type === 'auth-fail') {
        settled = true;
        resolve({ success: false, error: "Parol noto'g'ri" });
        client.close();
      }
    });

    client.on('error', (err) => {
      if (!settled) {
        settled = true;
        resolve({ success: false, error: err.message });
      }
    });

    client.on('close', () => {
      if (!settled) {
        settled = true;
        resolve({ success: false, error: "Ulanib bo'lmadi (server yopiq yoki band)" });
      }
      wsClient = null;
      if (mainWindow) mainWindow.webContents.send('viewer-connection-closed');
    });
  });
});

ipcMain.handle('disconnect-viewer', () => {
  if (wsClient) {
    wsClient.close();
    wsClient = null;
  }
  return { success: true };
});

ipcMain.on('viewer-mouse-event', (event, payload) => {
  if (wsClient && wsClient.readyState === WebSocket.OPEN) {
    wsClient.send(JSON.stringify(payload));
  }
});
