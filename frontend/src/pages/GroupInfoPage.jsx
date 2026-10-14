import { useEffect, useState } from 'react'
import {
  IoArrowBack,
  IoPersonAddOutline,
  IoTrashOutline,
  IoLogOutOutline,
  IoShieldOutline,
  IoShieldHalfOutline,
  IoGlobeOutline,
  IoLockClosedOutline,
} from 'react-icons/io5'
import { useNavigate, useParams } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import { api } from '../api'
import { avatarColor, initials } from '../utils'

const ROLE_LABEL = { admin: 'Admin', moderator: 'Moderator', member: 'Anggota' }
const ROLE_ICON = {
  admin: IoShieldOutline,
  moderator: IoShieldHalfOutline,
  member: null,
}

/* Dedicated group info page (route: /group/:id) */
export default function GroupInfoPage() {
  const { id } = useParams()
  const chatId = parseInt(id, 10)
  const { session, refreshChats } = useApp()
  const navigate = useNavigate()
  const [info, setInfo] = useState(null)
  const [name, setName] = useState('')
  const [editingName, setEditingName] = useState(false)
  const [newMember, setNewMember] = useState('')
  const [error, setError] = useState('')

  const load = () => {
    api.groupInfo(session.token, chatId)
      .then((d) => { setInfo(d.group); setName(d.group.name) })
      .catch(() => setError('Gagal memuat info grup.'))
  }

  useEffect(load, [session.token, chatId]) // eslint-disable-line

  const act = async (fn) => {
    setError('')
    try {
      await fn()
      await load()
      await refreshChats()
    } catch (e) {
      setError(actionError(e.message))
    }
  }

  if (!info) {
    return (
      <div className="pane page">
        <div className="page-header">
          <button className="icon-btn" onClick={() => navigate(-1)} aria-label="Kembali">
            <IoArrowBack />
          </button>
          <h2>Info Grup</h2>
        </div>
        <div className="empty">Memuat…</div>
      </div>
    )
  }

  const myRole = info.my_role
  const canManage = myRole === 'admin' || myRole === 'moderator'
  const isAdmin = myRole === 'admin'
  const me = session.username

  const leave = async () => {
    if (!window.confirm('Keluar dari grup?')) return
    await act(() => api.leaveGroup(session.token, chatId))
    navigate('/chats')
  }

  const remove = async () => {
    if (!window.confirm('Hapus grup permanen?')) return
    await act(() => api.deleteGroup(session.token, chatId))
    navigate('/chats')
  }

  return (
    <div className="pane page">
      <div className="page-header">
        <button className="icon-btn" onClick={() => navigate(-1)} aria-label="Kembali">
          <IoArrowBack />
        </button>
        <h2>Info Grup</h2>
      </div>
      <div className="page-body">
        {editingName && isAdmin ? (
          <div className="row-flex">
            <input
              className="input"
              value={name}
              maxLength={60}
              onChange={(e) => setName(e.target.value)}
            />
            <button className="btn-primary btn-sm"
              onClick={() => act(() => api.updateGroup(session.token, chatId, { name }))
                .then(() => setEditingName(false))}>
              OK
            </button>
          </div>
        ) : (
          <div className="row-flex between">
            <h2>{info.name}</h2>
            {isAdmin && (
              <button className="link-btn" style={{ marginTop: 0 }}
                onClick={() => setEditingName(true)}>
                Ubah
              </button>
            )}
          </div>
        )}
        <p className="muted">{info.members.length} anggota</p>

        {isAdmin && (
          <div className="seg" style={{ marginTop: '0.8rem' }}>
            <button
              className={info.visibility === 'private' ? 'active' : ''}
              onClick={() => act(() => api.updateGroup(session.token, chatId, { visibility: 'private' }))}
            >
              <IoLockClosedOutline /> Privat
            </button>
            <button
              className={info.visibility === 'public' ? 'active' : ''}
              onClick={() => act(() => api.updateGroup(session.token, chatId, { visibility: 'public' }))}
            >
              <IoGlobeOutline /> Publik
            </button>
          </div>
        )}

        {error && <div className="auth-error slim">{error}</div>}

        {canManage && (
          <div className="row-flex" style={{ marginTop: '0.8rem' }}>
            <input
              className="input"
              placeholder="Username anggota baru…"
              value={newMember}
              onChange={(e) => setNewMember(e.target.value)}
            />
            <button className="btn-primary btn-sm"
              onClick={() => {
                if (!newMember.trim()) return
                act(() => api.addGroupMember(session.token, chatId, newMember.trim()))
                  .then(() => setNewMember(''))
              }}>
              <IoPersonAddOutline />
            </button>
          </div>
        )}

        <div className="member-list" style={{ marginTop: '0.8rem' }}>
          {info.members.map(({ username, role }) => {
            const RI = ROLE_ICON[role]
            const targetHigher = role === 'admin' || (role === 'moderator' && myRole !== 'admin')
            return (
              <div key={username} className="member-row-static">
                <div className="avatar sm" style={{ background: avatarColor(username) }}>
                  {initials(username)}
                </div>
                <div className="chat-meta">
                  <strong>{username}{username === me ? ' (kamu)' : ''}</strong>
                  <span className="preview role">
                    {RI && <RI style={{ verticalAlign: -2 }} />} {ROLE_LABEL[role]}
                  </span>
                </div>
                {isAdmin && username !== me && role !== 'admin' && (
                  <select
                    className="role-select"
                    value={role}
                    onChange={(e) => act(() =>
                      api.setMemberRole(session.token, chatId, username, e.target.value))}
                  >
                    <option value="member">Anggota</option>
                    <option value="moderator">Moderator</option>
                    <option value="admin">Admin</option>
                  </select>
                )}
                {canManage && username !== me && !targetHigher && (
                  <button className="icon-btn sm danger" aria-label="Keluarkan"
                    onClick={() => {
                      if (!window.confirm(`Keluarkan ${username}?`)) return
                      act(() => api.removeGroupMember(session.token, chatId, username))
                    }}>
                    <IoTrashOutline />
                  </button>
                )}
              </div>
            )
          })}
        </div>

        <button className="setting-row" onClick={leave}>
          <IoLogOutOutline className="setting-icon danger" />
          <span className="danger-text">Keluar dari grup</span>
        </button>
        {isAdmin && (
          <button className="setting-row" onClick={remove}>
            <IoTrashOutline className="setting-icon danger" />
            <span className="danger-text">Hapus grup</span>
          </button>
        )}
      </div>
    </div>
  )
}

function actionError(code) {
  switch (code) {
    case 'forbidden': return 'Kamu tidak punya izin.'
    case 'unknown_user': return 'User tidak ditemukan.'
    case 'already_member': return 'Sudah jadi anggota.'
    default: return 'Gagal. Coba lagi.'
  }
}
