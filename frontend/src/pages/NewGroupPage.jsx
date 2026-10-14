import { useEffect, useState } from 'react'
import { IoArrowBack, IoPeopleOutline } from 'react-icons/io5'
import { useNavigate } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import { api } from '../api'
import { avatarColor, initials } from '../utils'

/* Dedicated new group page (route: /group/new) */
export default function NewGroupPage() {
  const { session, refreshChats } = useApp()
  const navigate = useNavigate()
  const [name, setName] = useState('')
  const [users, setUsers] = useState([])
  const [selected, setSelected] = useState(new Set())
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    api.contacts(session.token)
      .then((d) => setUsers(d.contacts.map((c) => c.username)))
      .catch(() => {})
  }, [session.token])

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
      const data = await api.createGroup(session.token, name.trim(), [...selected])
      await refreshChats()
      navigate(`/chats/${data.chat_id}`)
    } catch {
      setError('Gagal membuat grup. Coba lagi.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="pane page">
      <div className="page-header">
        <button className="icon-btn" onClick={() => navigate(-1)} aria-label="Kembali">
          <IoArrowBack />
        </button>
        <h2><IoPeopleOutline /> Grup Baru</h2>
      </div>
      <div className="page-body">
        <input
          className="input"
          placeholder="Nama grup…"
          value={name}
          maxLength={60}
          onChange={(e) => setName(e.target.value)}
          autoFocus
        />
        <p className="setting-label" style={{ margin: '1rem 0 0.4rem' }}>
          Pilih anggota dari kontak ({selected.size})
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
          {users.length === 0 && (
            <div className="empty">Belum ada kontak. Tambah via PIN dulu.</div>
          )}
        </div>
        {error && <div className="auth-error">{error}</div>}
        <button className="btn-primary btn-block" onClick={create} disabled={busy}>
          {busy ? 'Membuat…' : 'Buat Grup'}
        </button>
      </div>
    </div>
  )
}
