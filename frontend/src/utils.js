/* Shared helpers */

const AVATAR_COLORS = [
  'linear-gradient(135deg,#ff845e,#e13c5a)',
  'linear-gradient(135deg,#7b5cff,#b06bff)',
  'linear-gradient(135deg,#2481cc,#38bdf8)',
  'linear-gradient(135deg,#1faa6b,#4ade80)',
  'linear-gradient(135deg,#f59e0b,#fbbf24)',
  'linear-gradient(135deg,#ec4899,#a855f7)',
]

/* Deterministic gradient per username, like Telegram's colored avatars */
export function avatarColor(name = '?') {
  let h = 0
  for (const c of String(name)) h = (h * 31 + c.charCodeAt(0)) >>> 0
  return AVATAR_COLORS[h % AVATAR_COLORS.length]
}

export function initials(name = '?') {
  return String(name).slice(0, 2).toUpperCase()
}

export function fmtTime(ts) {
  return new Date(ts * 1000).toLocaleTimeString('id-ID', {
    hour: '2-digit',
    minute: '2-digit',
  })
}
