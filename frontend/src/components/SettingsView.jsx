import { useEffect, useState } from 'react'
import {
  IoLogOutOutline,
  IoInformationCircleOutline,
  IoPencilOutline,
  IoCheckmarkOutline,
  IoKeyOutline,
  IoCopyOutline,
} from 'react-icons/io5'
import { api } from '../api'
import { avatarColor, initials } from '../utils'

/* Profile + account settings */
export default function SettingsView({ token, me, onLogout }) {
  const [bio, setBio] = useState('')
  const [pin, setPin] = useState('')
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState('')
  const [saving, setSaving] = useState(false)
  const [copied, setCopied] = useState(false)

  useEffect(() => {
    api.me(token)
      .then((d) => { setBio(d.bio || ''); setPin(d.pin || '') })
      .catch(() => {})
  }, [token])

  const save = async () => {
    setSaving(true)
    try {
      await api.updateBio(token, draft)
      setBio(draft)
      setEditing(false)
    } catch { /* ignore */ }
    finally { setSaving(false) }
  }

  return (
    <div className="pane settings">
      <div className="profile-card">
        <div className="avatar xl" style={{ background: avatarColor(me) }}>
          {initials(me)}
        </div>
        <h2>{me}</h2>
        <span className="online">online</span>
      </div>

      <div className="settings-list">
        {/* BBM-style PIN */}
        <div className="setting-row static">
          <IoKeyOutline className="setting-icon" />
          <div style={{ flex: 1 }}>
            <span className="setting-label">PIN saya (ala BBM)</span>
            <strong className="pin-code">{pin || '…'}</strong>
            <p className="muted">Bagikan PIN ini biar teman bisa add kamu.</p>
          </div>
          <button
            className="icon-btn sm"
            aria-label="Salin PIN"
            onClick={() => {
              navigator.clipboard?.writeText(pin)
              setCopied(true)
              setTimeout(() => setCopied(false), 1500)
            }}
          >
            {copied ? <IoCheckmarkOutline /> : <IoCopyOutline />}
          </button>
        </div>

        <div className="setting-row static bio-row">
          <div className="bio-content">
            <span className="setting-label">Bio / Status</span>
            {editing ? (
              <div className="bio-edit">
                <input
                  className="input"
                  value={draft}
                  maxLength={160}
                  placeholder="Tulis bio singkat…"
                  onChange={(e) => setDraft(e.target.value)}
                  autoFocus
                />
                <div className="bio-actions">
                  <button className="btn-primary btn-sm" onClick={save} disabled={saving}>
                    <IoCheckmarkOutline /> Simpan
                  </button>
                  <button className="link-btn" onClick={() => setEditing(false)}>
                    Batal
                  </button>
                </div>
              </div>
            ) : (
              <div className="bio-view">
                <p className={bio ? '' : 'muted'}>
                  {bio || 'Belum ada bio. Ketuk ikon pensil untuk menambah.'}
                </p>
                <button
                  className="icon-btn sm"
                  aria-label="Ubah bio"
                  onClick={() => { setDraft(bio); setEditing(true) }}
                >
                  <IoPencilOutline />
                </button>
              </div>
            )}
          </div>
        </div>

        <button className="setting-row" onClick={onLogout}>
          <IoLogOutOutline className="setting-icon danger" />
          <span className="danger-text">Keluar</span>
        </button>

        <div className="setting-row static">
          <IoInformationCircleOutline className="setting-icon" />
          <div>
            <strong>Telegram Clone v1.1</strong>
            <p className="muted">Erlang + React · Mnesia · WebSocket</p>
          </div>
        </div>
      </div>
    </div>
  )
}
