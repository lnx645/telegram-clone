/* Tiny API client for the Erlang backend (same origin). */

const BASE = '/api'

function headers(token) {
  return {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${token}`,
  }
}

async function req(method, path, token, body) {
  const res = await fetch(BASE + path, {
    method,
    headers: headers(token),
    body: body ? JSON.stringify(body) : undefined,
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok || data.ok === false) {
    throw new Error(data.error || `http_${res.status}`)
  }
  return data
}

export const api = {
  register: (username, password) =>
    req('POST', '/register', '', { username, password }),
  login: (username, password) =>
    req('POST', '/login', '', { username, password }),
  logout: (token) => req('POST', '/logout', token),
  me: (token) => req('GET', '/me', token),
  updateBio: (token, bio) => req('PUT', '/profile', token, { bio }),

  // Contacts (BBM-style PIN)
  contacts: (token) => req('GET', '/contacts', token),
  contactRequests: (token) => req('GET', '/contacts/requests', token),
  sendContactRequest: (token, pin) =>
    req('POST', '/contacts/requests', token, { pin }),
  acceptRequest: (token, from) =>
    req('POST', `/contacts/requests/${from}/accept`, token),
  declineRequest: (token, from) =>
    req('POST', `/contacts/requests/${from}/decline`, token),
  removeContact: (token, username) =>
    req('DELETE', `/contacts/${username}`, token),
  searchUsers: (token, q) =>
    req('GET', `/users?q=${encodeURIComponent(q)}`, token),

  // Chats & groups
  listChats: (token) => req('GET', '/chats', token),
  openChat: (token, username) =>
    req('POST', '/chats', token, { username }),
  createGroup: (token, name, members) =>
    req('POST', '/groups', token, { name, members }),
  groupInfo: (token, chatId) => req('GET', `/groups/${chatId}`, token),
  updateGroup: (token, chatId, patch) =>
    req('PUT', `/groups/${chatId}`, token, patch),
  deleteGroup: (token, chatId) =>
    req('DELETE', `/groups/${chatId}`, token),
  publicGroups: (token) => req('GET', '/groups/public', token),
  joinGroup: (token, chatId) =>
    req('POST', `/groups/${chatId}/join`, token),
  leaveGroup: (token, chatId) =>
    req('POST', `/groups/${chatId}/leave`, token),
  addGroupMember: (token, chatId, username) =>
    req('POST', `/groups/${chatId}/members`, token, { username }),
  removeGroupMember: (token, chatId, username) =>
    req('DELETE', `/groups/${chatId}/members/${username}`, token),
  setMemberRole: (token, chatId, username, role) =>
    req('PUT', `/groups/${chatId}/members/${username}/role`, token, { role }),

  // Messages
  listMessages: (token, chatId) =>
    req('GET', `/chats/${chatId}/messages`, token),
  markRead: (token, chatId) =>
    req('POST', `/chats/${chatId}/read`, token),
  send: (token, chatId, { kind = 'text', text = '', media_url, reply_to }) =>
    req('POST', `/chats/${chatId}/messages`, token,
        { kind, text, media_url, reply_to }),
  deleteMessage: (token, chatId, msgId, mode = 'me') =>
    req('DELETE', `/chats/${chatId}/messages/${msgId}?mode=${mode}`, token),
  addReaction: (token, msgId, emoji) =>
    req('POST', `/messages/${msgId}/reactions`, token, { emoji }),
  removeReaction: (token, msgId) =>
    req('DELETE', `/messages/${msgId}/reactions`, token),

  // Status
  postStatus: (token, payload) => req('POST', '/status', token, payload),
  statusFeed: (token) => req('GET', '/status/feed', token),
  deleteStatus: (token, id) => req('DELETE', `/status/${id}`, token),
  viewStatus: (token, id) => req('POST', `/status/${id}/view`, token),

  uploadMedia: async (token, file) => {
    const form = new FormData()
    form.append('file', file)
    const res = await fetch(`${BASE}/upload`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: form,
    })
    const data = await res.json().catch(() => ({}))
    if (!res.ok || data.ok === false) {
      throw new Error(data.error || `http_${res.status}`)
    }
    return data.url
  },
}

export const STICKERS = Array.from({ length: 12 }, (_, i) =>
  `/stickers/s${String(i + 1).padStart(2, '0')}.svg`
)

export const REACTION_EMOJIS = ['❤️', '😂', '😮', '😢', '🙏', '👍']

export const STATUS_COLORS = ['#2aabee', '#7b5cff', '#e13c5a', '#1faa6b', '#f59e0b', '#0e1621']

export function wsUrl(token) {
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${proto}//${window.location.host}/ws?token=${encodeURIComponent(token)}`
}

export function presenceLabel(p) {
  if (!p) return ''
  if (p.online) return 'online'
  if (p.last_seen) {
    const d = new Date(p.last_seen * 1000)
    const now = new Date()
    const sameDay = d.toDateString() === now.toDateString()
    const t = d.toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' })
    return sameDay ? `terakhir dilihat ${t}` : `terakhir dilihat ${d.toLocaleDateString('id-ID')} ${t}`
  }
  return 'offline'
}
