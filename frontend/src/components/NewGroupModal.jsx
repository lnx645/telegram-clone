import { useEffect, useState } from 'react'
import { IoClose, IoPeopleOutline } from 'react-icons/io5'
import { api } from '../api'
import { avatarColor, initials } from '../utils'

/* Create a new group chat */
export default function NewGroupModal({ token, me, onClose, onCreated }) {
  const [name, setName] = useState('')
  const [users, setUsers] = useState([])
  const [selected, setSelected] = useState(new Set())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    api.searchUsers(token, '')
      .then((d) => setUsers(d.users.map((u) => u.username || u)))
      .catch(() => {})
  }, [token])

  const toggle = (u) => {
    setSelected((s) => {
      const n = new Set(s)
      if (n.has(u)) n.delete(u)
      else n.add(u)
      return n
    })
  }

  const create = async () => {
    setError('')
    if (!name.trim()) { setError('Nama grup wajib diisi.'); return }
    if (selected.size === 0) { setError('Pilih minimal 1 anggota.'); return }
    setBusy(true)
    try {
      const data = await api.createGroup(token, name.trim(), [...selected])
      onCreated(data.chat_id)
    } catch (e) {
      setError('Gagal membuat grup. Coba lagi.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3><IoPeopleOutline /> Grup Baru</h3>
          <button className="icon-btn sm" onClick={onClose} aria-label="Tutup">
            <IoClose />
          </button>
        </div>
        <input
          className="input"
          placeholder="Nama grup…"
          value={name}
          maxLength={60}
          onChange={(e) => setName(e.target.value)}
          autoFocus
        />
        <p className="setting-label" style={{ margin: '0.8rem 0 0.4rem' }}>
          Pilih anggota ({selected.size})
        </p>
        <div className="member-list">
          {users.map((u) => (
            <label key={u} className="member-row">
              <input
                type="checkbox"
                checked={selected.has(u)}
                onChange={() => toggle(u)}
              />
              <div className="avatar sm" style={{ background: avatarColor(u) }}>
                {initials(u)}
              </div>
              <span>{u}</span>
            </label>
          ))}
          {users.length === 0 && <div className="empty">Tidak ada user lain.</div>}
        </div>
        {error && <div className="auth-error">{error}</div>}
        <button className="btn-primary btn-block" onClick={create} disabled={busy}>
          {busy ? 'Membuat…' : 'Buat Grup'}
        </button>
      </div>
    </div>
  )
}
