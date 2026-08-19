const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  getLocalIps: () => ipcRenderer.invoke('get-local-ips'),
  getScreenSources: () => ipcRenderer.invoke('get-screen-sources'),
  checkMacPermissions: () => ipcRenderer.invoke('check-mac-permissions'),

  // Host mode
  startHost: (opts) => ipcRenderer.invoke('start-host', opts),
  stopHost: () => ipcRenderer.invoke('stop-host'),
  sendFrame: (buffer) => ipcRenderer.send('host-frame', buffer),
  onViewerConnected: (cb) => ipcRenderer.on('viewer-connected', () => cb()),
  onViewerDisconnected: (cb) => ipcRenderer.on('viewer-disconnected', () => cb()),
  onHostServerError: (cb) => ipcRenderer.on('host-server-error', (e, msg) => cb(msg)),

  // Viewer mode
  connectViewer: (opts) => ipcRenderer.invoke('connect-viewer', opts),
  disconnectViewer: () => ipcRenderer.invoke('disconnect-viewer'),
  onFrame: (cb) => ipcRenderer.on('frame', (e, data) => cb(data)),
  onConnectionClosed: (cb) => ipcRenderer.on('viewer-connection-closed', () => cb()),
  sendMouseEvent: (payload) => ipcRenderer.send('viewer-mouse-event', payload),
});
