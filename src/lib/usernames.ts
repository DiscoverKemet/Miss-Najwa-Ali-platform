// Shared, browser-safe helpers for username-based auth.
// Auth requires an email, so every account uses a deterministic internal address
// derived from the normalized username. No email is ever sent to it.
export const INTERNAL_EMAIL_DOMAIN = "accounts.missnajwa.app";

export function normalizeUsername(raw: string) {
  return raw.trim().toLowerCase();
}

export const USERNAME_RE = /^[a-z0-9_.]{3,32}$/;

export function usernameToEmail(username: string) {
  return `${normalizeUsername(username)}@${INTERNAL_EMAIL_DOMAIN}`;
}
