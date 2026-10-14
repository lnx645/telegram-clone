import { useEffect, useState } from 'react'
import {
  IoSearch,
  IoChatbubblesOutline,
  IoPersonAddOutline,
  IoCheckmarkOutline,
  IoCloseOutline,
  IoTrashOutline,
} from 'react-icons/io5'
import { api, presenceLabel } from '../api'
import { avatarColor, initials } from '../utils'

/* My contacts (BBM-style): added via PIN, with request inbox */
export default function ContactsView({ token, onOpen }) {
  const [contacts, setContacts] = useState([])
  const [incoming, setIncoming] = useState([])
  const [outgoing, setOutgoing] = useState([])
  const [q, setQ] = useState('')
  const [pin, setPin] = useState('')
  const [adding, setAdding] = useState(false)
  const [error, setError] = useState('')
  const [okMsg, setOkMsg] = useState('')

  const load = () => {
    api.contacts(token).then((d) => setContacts(d.contacts)).catch(() => {})
    api.contactRequests(token)
      .then((d) => { setIncoming(d.incoming); setOutgoing(d.outgoing) })
      .catch(() => {})
  }

  useEffect(load, [token]) // eslint-disable-line

  const sendRequest = async (e) => {
    e.preventDefault()
    setError(''); setOkMsg('')
    if (!pin.trim()) return
    setAdding(true)
    try {
      await api.sendContactRequest(token, pin.trim())
      setPin('')
      setOkMsg('Permintaan terkirim!')
      load()
    } catch (err) {
      setError(pinError(err.message))
    } finally {
      setAdding(false)
    }
  }

  const respond = async (from, accept) => {
    try {
      if (accept) await api.acceptRequest(token, from)
      else await api.declineRequest(token, from)
      load()
    } catch { /* ignore */ }
  }

  const remove = async (username) => {
    if (!window.confirm(`Hapus ${username} dari kontak?`)) return
    try {
      await api.removeContact(token, username)
      load()
    } catch { /* ignore */ }
  }

  const filtered = contacts.filter((c) =>
    c.username.toLowerCase().includes(q.toLowerCase())
  )

  return (
    <div className="pane">
      <form className="add-contact" onSubmit={sendRequest}>
        <div className="search-box grow">
          <IoPersonAddOutline className="search-icon" />
          <input
            className="input search-input"
            placeholder="Tambah via PIN (cth: A1B2C3D4)…"
            value={pin}
            onChange={(e) => setPin(e.target.value.toUpperCase())}
            maxLength={8}
          />
        </div>
        <button className="btn-primary btn-sm" disabled={adding}>
          {adding ? '…' : 'Tambah'}
        </button>
      </form>
      {error && <div className="auth-error slim">{error}</div>}
      {okMsg && <div className="ok-msg slim">{okMsg}</div>}

      {incoming.length > 0 && (
        <div className="req-section">
          <p className="setting-label">Permintaan masuk ({incoming.length})</p>
          {incoming.map(({ username }) => (
            <div key={username} className="chat-item static">
              <div className="avatar sm" style={{ background: avatarColor(username) }}>
                {initials(username)}
              </div>
              <div className="chat-meta"><strong>{username}</strong></div>
              <button className="icon-btn sm accept" aria-label="Terima"
                onClick={() => respond(username, true)}>
                <IoCheckmarkOutline />
              </button>
              <button className="icon-btn sm" aria-label="Tolak"
                onClick={() => respond(username, false)}>
                <IoCloseOutline />
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="search-box">
        <IoSearch className="search-icon" />
        <input
          className="input search-input"
          placeholder="Cari kontak…"
          value={q}
          onChange={(e) => setQ(e.target.value)}
        />
      </div>

      <div className="chat-list">
        {filtered.length === 0 && (
          <div className="empty">
            Belum ada kontak.<br />
            Minta PIN temanmu untuk menambahkannya.
          </div>
        )}
        {filtered.map(({ username, presence, bio }) => (
          <div key={username} className="chat-item static">
            <div className="avatar sm" style={{ background: avatarColor(username) }}>
              {initials(username)}
            </div>
            <div className="chat-meta" onClick={() => onOpen(username)} style={{ cursor: 'pointer' }}>
              <strong>{username}</strong>
              <span className={`preview${presence?.online ? ' online-text' : ''}`}>
                {bio || presenceLabel(presence)}
              </span>
            </div>
            <button className="icon-btn sm" aria-label="Chat"
              onClick={() => onOpen(username)}>
              <IoChatbubblesOutline className="row-icon" />
            </button>
            <button className="icon-btn sm danger" aria-label="Hapus kontak"
              onClick={() => remove(username)}>
              <IoTrashOutline />
            </button>
          </div>
        ))}
      </div>
    </div>
  )
}

function pinError(code) {
  switch (code) {
    case 'unknown_pin': return 'PIN tidak ditemukan.'
    case 'cannot_add_self': return 'Itu PIN kamu sendiri.'
    case 'already_contacts': return 'Sudah jadi kontak.'
    case 'request_pending': return 'Permintaan sudah terkirim.'
    default: return 'Gagal mengirim permintaan.'
  }
}
