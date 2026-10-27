/** Suggested job positions. Free text is also allowed — this is a starting point, not a closed set. */
export const POSITION_PRESETS = [
  "Sales",
  "Technical Support",
  "Finance",
  "HR",
  "Operation Manager",
  "General Manager",
  "Supervisor",
  "Engineer",
] as const;

export const AVATAR_BUCKET = "avatars";

/** Matches the bucket limit set in the migration. */
export const MAX_AVATAR_BYTES = 2 * 1024 * 1024;

export const AVATAR_MIME_TYPES = [
  "image/png",
  "image/jpeg",
  "image/webp",
  "image/gif",
];

/**
 * Object key for an avatar upload.
 *
 * The user id is the first path segment because the storage policy reads it to
 * decide who may write here. The timestamp busts the CDN cache, which would
 * otherwise keep serving the previous picture from the same public URL.
 */
export function avatarPath(userId: string, fileName: string): string {
  const extension = fileName.toLowerCase().match(/\.(png|jpe?g|webp|gif)$/)?.[0] ?? ".png";
  return `${userId}/avatar-${Date.now()}${extension}`;
}
