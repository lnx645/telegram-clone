import { useEffect, useState } from 'react'
import { IoAdd, IoTrashOutline, IoEyeOutline } from 'react-icons/io5'
import { useNavigate } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import { api } from '../api'
import { avatarColor, initials } from '../utils'
import { StatusThumb } from '../components/StatusView'

/* WhatsApp-style Status page (route: /status) */
export default function StatusPage() {
  const { session, statusKey, bumpStatusKey } = useApp()
  const navigate = useNavigate()
  const [mine, setMine] = useState([])
  const [feed, setFeed] = useState([])

  const load = () => {
    api.statusFeed(session.token)
      .then((d) => { setMine(d.mine); setFeed(d.feed) })
      .catch(() => {})
  }

  useEffect(load, [session.token, statusKey]) // eslint-disable-line

  const del = async (id) => {
    if (!window.confirm('Hapus status ini?')) return
    try {
      await api.deleteStatus(session.token, id)
      load()
      bumpStatusKey()
    } catch { /* ignore */ }
  }

  return (
    <div className="pane">
      <div className="chat-list">
        <div className="status-section">
          <p className="setting-label">Status saya</p>
          <button className="chat-item" onClick={() => navigate('/status/compose')}>
            <div className="avatar sm status-add" style={{ background: avatarColor(session.username) }}>
              {initials(session.username)}
              <span className="status-plus"><IoAdd /></span>
            </div>
            <div className="chat-meta">
              <strong>Status saya</strong>
              <span className="preview">
                {mine.length > 0 ? `${mine.length} update` : 'Ketuk untuk tambah update'}
              </span>
            </div>
          </button>
          {mine.map((s) => (
            <div key={s.id} className="chat-item static">
              <StatusThumb s={s} />
              <div className="chat-meta">
                <span className="preview">
                  {new Date(s.ts * 1000).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' })}
                  {' · '}
                  <IoEyeOutline style={{ verticalAlign: -2 }} /> {s.views}
                </span>
              </div>
              <button className="icon-btn sm danger" onClick={() => del(s.id)} aria-label="Hapus">
                <IoTrashOutline />
              </button>
            </div>
          ))}
        </div>

        <div className="status-section">
          <p className="setting-label">Update terbaru</p>
          {feed.length === 0 && (
            <div className="empty">Belum ada update dari kontak.</div>
          )}
          {feed.map(({ username, statuses, all_viewed }) => (
            <button
              key={username}
              className="chat-item"
              onClick={() => navigate(`/status/view/${username}`, { state: { statuses } })}
            >
              <div className={`avatar sm${all_viewed ? '' : ' has-status'}`}
                style={{ background: avatarColor(username) }}>
                {initials(username)}
              </div>
              <div className="chat-meta">
                <strong>{username}</strong>
                <span className="preview">
                  {statuses.length} update · {timeAgo(statuses[0].ts)}
                </span>
              </div>
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

function timeAgo(ts) {
  const mins = Math.floor((Date.now() / 1000 - ts) / 60)
  if (mins < 1) return 'baru saja'
  if (mins < 60) return `${mins} mnt lalu`
  const h = Math.floor(mins / 60)
  if (h < 24) return `${h} jam lalu`
  return `${Math.floor(h / 24)} hari lalu`
}
