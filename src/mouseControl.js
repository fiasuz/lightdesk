// Injects real mouse movement/clicks/scroll on THIS machine (host side).
// Uses nut-js, which talks to the OS input APIs directly (Windows: SendInput,
// macOS: CGEvent) so it works whether or not the window is focused.
const { mouse, Point, Button, screen } = require('@nut-tree-fork/nut-js');

mouse.config.mouseSpeed = 3000; // fast, near-instant moves feel more like a real remote cursor
mouse.config.autoDelayMs = 0;

// nut-js moves the cursor in hardware-pixel coordinates, which on
// high-DPI/scaled displays differ from Electron's screen.getPrimaryDisplay()
// (that reports logical/DIP pixels). Using nut-js's own screen size here
// keeps mouse-move math in the same coordinate space mouse.setPosition uses,
// instead of drifting further off the further the cursor gets from (0,0).
async function getScreenSize() {
  const width = await screen.width();
  const height = await screen.height();
  return { width, height };
}

function buttonFor(name) {
  if (name === 'right') return Button.RIGHT;
  if (name === 'middle') return Button.MIDDLE;
  return Button.LEFT;
}

async function move(x, y) {
  await mouse.setPosition(new Point(Math.round(x), Math.round(y)));
}

async function down(button) {
  await mouse.pressButton(buttonFor(button));
}

async function up(button) {
  await mouse.releaseButton(buttonFor(button));
}

async function scroll(deltaX, deltaY) {
  if (deltaY) {
    if (deltaY > 0) await mouse.scrollDown(Math.min(Math.round(deltaY), 50));
    else await mouse.scrollUp(Math.min(Math.round(-deltaY), 50));
  }
  if (deltaX) {
    if (deltaX > 0) await mouse.scrollRight(Math.min(Math.round(deltaX), 50));
    else await mouse.scrollLeft(Math.min(Math.round(-deltaX), 50));
  }
}

module.exports = { move, down, up, scroll, getScreenSize };
