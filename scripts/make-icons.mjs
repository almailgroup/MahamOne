// Cuts the Maham One logo out of brand/maham-one-logo-source.png and renders
// every image the app uses from it:
//   public/brand/maham-one-logo.png       the logo (mark and name), transparent
//   public/brand/maham-one-logo-dark.png  the same with a white "Maham", for dark themes
//   public/brand/maham-one-mark.png       the mark alone, transparent
//   public/brand/maham-one-logo-email.png the logo on a white plate, for emails
//   public/icons/favicon-64.png           the browser tab's icon
//   public/icons/icon-192.png, icon-512.png, maskable-512.png, apple-touch-icon.png
//   ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png  the iPhone app's icon
// Usage: node scripts/make-icons.mjs
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createCanvas, loadImage } from '@napi-rs/canvas';
import { PNG } from 'pngjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const source = await loadImage(join(root, 'brand/maham-one-logo-source.png'));

// Where things are in the source (pixels): the mark, the whole logo, "Maham" in the name.
const MARK = { x0: 175, y0: 287, x1: 524, y1: 566 };
const LOGO = { x0: 175, y0: 287, x1: 1614, y1: 566 };
const MAHAM = { x0: 600, x1: 1245 };
// The paper the logo was drawn on.
const PAPER = 254;

/** The source with its paper taken out: each pixel's own colour, and how much of it there is. */
function cutOut() {
  const canvas = createCanvas(source.width, source.height);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(source, 0, 0);
  const image = ctx.getImageData(0, 0, source.width, source.height);
  const d = image.data;
  for (let i = 0; i < d.length; i += 4) {
    // Colour to alpha: how far a channel is from the paper decides the opacity, and the
    // colour is the one that, laid on the paper at that opacity, looks the same.
    let alpha = 0;
    for (let k = 0; k < 3; k++) alpha = Math.max(alpha, Math.max(0, PAPER - d[i + k]) / PAPER);
    // Compression specks around the shapes.
    if (alpha < 0.05) {
      d[i + 3] = 0;
      continue;
    }
    for (let k = 0; k < 3; k++) {
      const c = Math.min(d[i + k], PAPER);
      d[i + k] = Math.round(Math.max(0, Math.min(255, PAPER - (PAPER - c) / alpha)));
    }
    d[i + 3] = Math.round(alpha * 255);
  }
  ctx.putImageData(image, 0, 0);
  return { canvas, ctx, image };
}

/** "Maham" in white, for dark themes; "One" and the mark keep their blues. */
function whiteName(image) {
  const d = image.data;
  for (let i = 0; i < d.length; i += 4) {
    const x = (i / 4) % image.width;
    if (x < MAHAM.x0 || x > MAHAM.x1 || d[i + 3] === 0) continue;
    if (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2] < 90) {
      d[i] = 241;
      d[i + 1] = 245;
      d[i + 2] = 249;
    }
  }
  return image;
}

/** A part of the cut-out, with `pad` source pixels around it, scaled to `height`. */
function crop(canvas, box, height, pad = 6) {
  const w = box.x1 - box.x0 + 1 + pad * 2;
  const h = box.y1 - box.y0 + 1 + pad * 2;
  const out = createCanvas(Math.round((w * height) / h), height);
  const ctx = out.getContext('2d');
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(canvas, box.x0 - pad, box.y0 - pad, w, h, 0, 0, out.width, height);
  return out;
}

/** The mark centred on a square, `share` of its side, on `background` (none: transparent). */
function square(canvas, size, share, { background = null, radius = 0 } = {}) {
  const out = createCanvas(size, size);
  const ctx = out.getContext('2d');
  if (background) {
    ctx.fillStyle = background;
    ctx.beginPath();
    ctx.roundRect(0, 0, size, size, radius);
    ctx.fill();
  }
  const w = MARK.x1 - MARK.x0 + 1;
  const h = MARK.y1 - MARK.y0 + 1;
  const scale = (size * share) / Math.max(w, h);
  const dw = w * scale;
  const dh = h * scale;
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(canvas, MARK.x0, MARK.y0, w, h, (size - dw) / 2, (size - dh) / 2, dw, dh);
  return out;
}

/**
 * The logo on a white, rounded plate. Mail apps that darken emails (Gmail, Outlook)
 * leave images as they are: on its own white the navy "Maham" stays readable.
 */
function plate(logo, pad, radius) {
  const out = createCanvas(logo.width + pad * 2, logo.height + pad * 2);
  const ctx = out.getContext('2d');
  ctx.fillStyle = '#ffffff';
  ctx.beginPath();
  ctx.roundRect(0, 0, out.width, out.height, radius);
  ctx.fill();
  ctx.drawImage(logo, pad, pad);
  return out;
}

function save(canvas, path) {
  const file = join(root, path);
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file, canvas.toBuffer('image/png'));
  console.log(`${path} (${canvas.width}×${canvas.height})`);
}

const light = cutOut();
const logo = crop(light.canvas, LOGO, 192);
save(logo, 'public/brand/maham-one-logo.png');
save(plate(crop(light.canvas, LOGO, 112), 24, 24), 'public/brand/maham-one-logo-email.png');
save(square(light.canvas, 256, 1), 'public/brand/maham-one-mark.png');
save(square(light.canvas, 64, 0.94), 'public/icons/favicon-64.png');
// The installed app: the mark on a white tile, so it reads on any wallpaper or dock.
save(
  square(light.canvas, 192, 0.66, { background: '#ffffff', radius: 42 }),
  'public/icons/icon-192.png',
);
save(
  square(light.canvas, 512, 0.66, { background: '#ffffff', radius: 112 }),
  'public/icons/icon-512.png',
);
// Maskable icons keep their content inside the central 80% circle; iOS rounds its own corners.
save(square(light.canvas, 512, 0.5, { background: '#ffffff' }), 'public/icons/maskable-512.png');
save(
  square(light.canvas, 180, 0.62, { background: '#ffffff' }),
  'public/icons/apple-touch-icon.png',
);

// The iPhone app: iOS rounds the corners and adds its own glass, and the App
// Store refuses an icon with an alpha channel, so the tile is square, white
// and saved without one.
const ios = square(light.canvas, 1024, 0.62, { background: '#ffffff' });
const rgba = ios.getContext('2d').getImageData(0, 0, 1024, 1024).data;
const opaque = new PNG({ width: 1024, height: 1024, colorType: 2, inputHasAlpha: true });
opaque.data = Buffer.from(rgba);
const iosIcon = 'ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png';
mkdirSync(join(root, dirname(iosIcon)), { recursive: true });
writeFileSync(join(root, iosIcon), PNG.sync.write(opaque, { colorType: 2 }));
console.log(`${iosIcon} (1024×1024, no alpha)`);

const dark = cutOut();
dark.ctx.putImageData(whiteName(dark.image), 0, 0);
save(crop(dark.canvas, LOGO, 192), 'public/brand/maham-one-logo-dark.png');
