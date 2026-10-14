import { useEffect, useState } from 'react'
import {
  IoClose,
  IoPersonAddOutline,
  IoTrashOutline,
  IoLogOutOutline,
  IoShieldOutline,
  IoShieldHalfOutline,
  IoGlobeOutline,
  IoLockClosedOutline,
} from 'react-icons/io5'
import { api } from '../api'
import { avatarColor, initials } from '../utils'

const ROLE_LABEL = { admin: 'Admin', moderator: 'Moderator', member: 'Anggota' }
const ROLE_ICON = {
  admin: IoShieldOutline,
  moderator: IoShieldHalfOutline,
  member: null,
}

/* Group info & management: members, roles, visibility */
export default function GroupInfoModal({ token, me, chatId, onClose, onChanged }) {
  const [info, setInfo] = useState(null)
  const [name, setName] = useState('')
  const [editingName, setEditingName] = useState(false)
  const [newMember, setNewMember] = useState('')
  const [error, setError] = useState('')

  const load = () => {
    api.groupInfo(token, chatId)
      .then((d) => { setInfo(d.group); setName(d.group.name) })
      .catch(() => setError('Gagal memuat info grup.'))
  }

  useEffect(load, [token, chatId]) // eslint-disable-line

  const act = async (fn, okMsg) => {
    setError('')
    try {
      await fn()
      await load()
      onChanged?.()
    } catch (e) {
      setError(actionError(e.message))
    }
  }

  if (!info) {
    return (
      <div className="modal-backdrop" onClick={onClose}>
        <div className="modal"><div className="empty">Memuat…</div></div>
      </div>
    )
  }

  const myRole = info.my_role
  const canManage = myRole === 'admin' || myRole === 'moderator'
  const isAdmin = myRole === 'admin'

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3>Info Grup</h3>
          <button className="icon-btn sm" onClick={onClose} aria-label="Tutup">
            <IoClose />
          </button>
        </div>

        {/* Name */}
        {editingName && isAdmin ? (
          <div className="row-flex">
            <input
              className="input"
              value={name}
              maxLength={60}
              onChange={(e) => setName(e.target.value)}
            />
            <button className="btn-primary btn-sm"
              onClick={() => act(() => api.updateGroup(token, chatId, { name }), 'ok')
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

        {/* Visibility */}
        {isAdmin && (
          <div className="seg">
            <button
              className={info.visibility === 'private' ? 'active' : ''}
              onClick={() => act(() => api.updateGroup(token, chatId, { visibility: 'private' }))}
            >
              <IoLockClosedOutline /> Privat
            </button>
            <button
              className={info.visibility === 'public' ? 'active' : ''}
              onClick={() => act(() => api.updateGroup(token, chatId, { visibility: 'public' }))}
            >
              <IoGlobeOutline /> Publik
            </button>
          </div>
        )}

        {error && <div className="auth-error slim">{error}</div>}

        {/* Add member */}
        {canManage && (
          <div className="row-flex">
            <input
              className="input"
              placeholder="Username anggota baru…"
              value={newMember}
              onChange={(e) => setNewMember(e.target.value)}
            />
            <button className="btn-primary btn-sm"
              onClick={() => {
                if (!newMember.trim()) return
                act(() => api.addGroupMember(token, chatId, newMember.trim()))
                  .then(() => setNewMember(''))
              }}>
              <IoPersonAddOutline />
            </button>
          </div>
        )}

        {/* Members */}
        <div className="member-list">
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
                      api.setMemberRole(token, chatId, username, e.target.value))}
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
                      act(() => api.removeGroupMember(token, chatId, username))
                    }}>
                    <IoTrashOutline />
                  </button>
                )}
              </div>
            )
          })}
        </div>

        {/* Leave / delete */}
        <button
          className="setting-row"
          onClick={() => {
            if (!window.confirm('Keluar dari grup?')) return
            act(() => api.leaveGroup(token, chatId)).then(onClose)
          }}
        >
          <IoLogOutOutline className="setting-icon danger" />
          <span className="danger-text">Keluar dari grup</span>
        </button>
        {isAdmin && (
          <button
            className="setting-row"
            onClick={() => {
              if (!window.confirm('Hapus grup permanen?')) return
              act(() => api.deleteGroup(token, chatId)).then(onClose)
            }}
          >
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
