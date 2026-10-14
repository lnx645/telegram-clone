import { useEffect, useRef, useState } from 'react'
import { IoClose, IoEyeOutline } from 'react-icons/io5'
import { api } from '../api'
import { avatarColor, initials } from '../utils'

const DURATION = 5000 // ms per status

/* Fullscreen status viewer with progress bars */
export default function StatusViewer({ token, me, username, statuses, onClose, onDone }) {
  const [idx, setIdx] = useState(0)
  const [progress, setProgress] = useState(0)
  const timer = useRef(null)
  const startRef = useRef(Date.now())

  const s = statuses[idx]

  useEffect(() => {
    if (!s) { onDone(); return }
    // Mark as viewed (not for own statuses)
    if (username !== me) api.viewStatus(token, s.id).catch(() => {})
    setProgress(0)
    startRef.current = Date.now()
    clearInterval(timer.current)
    timer.current = setInterval(() => {
      const el = Date.now() - startRef.current
      setProgress(Math.min(1, el / DURATION))
      if (el >= DURATION) {
        clearInterval(timer.current)
        if (idx + 1 < statuses.length) setIdx(idx + 1)
        else onDone()
      }
    }, 50)
    return () => clearInterval(timer.current)
  }, [idx, s?.id]) // eslint-disable-line

  if (!s) return null

  const go = (d) => {
    if (d < 0 && idx > 0) setIdx(idx - 1)
    else if (d > 0) {
      if (idx + 1 < statuses.length) setIdx(idx + 1)
      else onDone()
    }
  }

  return (
    <div className="status-viewer">
      <div className="sv-progress">
        {statuses.map((_, i) => (
          <div key={i} className="sv-bar">
            <div
              className="sv-fill"
              style={{ width: `${i < idx ? 100 : i === idx ? progress * 100 : 0}%` }}
            />
          </div>
        ))}
      </div>
      <div className="sv-header">
        <div className="avatar sm" style={{ background: avatarColor(username) }}>
          {initials(username)}
        </div>
        <div className="sv-meta">
          <strong>{username}</strong>
          <span>{new Date(s.ts * 1000).toLocaleTimeString('id-ID', { hour: '2-digit', minute: '2-digit' })}</span>
        </div>
        {username === me && (
          <span className="sv-views"><IoEyeOutline /> {s.views}</span>
        )}
        <button className="icon-btn" onClick={onClose} aria-label="Tutup">
          <IoClose />
        </button>
      </div>

      <div className="sv-body" onClick={(e) => {
        const x = e.clientX / window.innerWidth
        go(x < 0.3 ? -1 : 1)
      }}>
        {s.kind === 'text' && (
          <div className="sv-text" style={{ background: s.bg_color || '#2aabee' }}>
            {s.text}
          </div>
        )}
        {s.kind === 'image' && <img src={s.media_url} alt="" />}
        {s.kind === 'video' && <video src={s.media_url} autoPlay muted playsInline />}
      </div>
    </div>
  )
}
