import { useRef, useState } from 'react'
import {
  IoArrowBack,
  IoSend,
  IoImageOutline,
  IoTextOutline,
  IoHappyOutline,
} from 'react-icons/io5'
import { useNavigate } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import { api, STATUS_COLORS } from '../api'

/* Dedicated fullscreen status composer (WhatsApp-style, route: /status/compose) */
export default function StatusComposePage() {
  const { session, bumpStatusKey } = useApp()
  const navigate = useNavigate()
  const [mode, setMode] = useState('text')
  const [text, setText] = useState('')
  const [bg, setBg] = useState(STATUS_COLORS[0])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const fileRef = useRef(null)

  const back = () => navigate('/status')

  const postText = async () => {
    if (!text.trim()) { setError('Tulis sesuatu dulu.'); return }
    setBusy(true); setError('')
    try {
      await api.postStatus(session.token, { kind: 'text', text: text.trim(), bg_color: bg })
      bumpStatusKey()
      navigate('/status')
    } catch {
      setError('Gagal memposting.')
    } finally { setBusy(false) }
  }

  const postMedia = async (e) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    const kind = file.type.startsWith('image/') ? 'image'
      : file.type.startsWith('video/') ? 'video' : null
    if (!kind) { setError('Hanya foto/video.'); return }
    setBusy(true); setError('')
    try {
      const url = await api.uploadMedia(session.token, file)
      await api.postStatus(session.token, { kind, media_url: url })
      bumpStatusKey()
      navigate('/status')
    } catch {
      setError('Gagal mengunggah.')
    } finally { setBusy(false) }
  }

  return (
    <div className="composer-page">
      <div className="cp-header">
        <button className="icon-btn" onClick={back} aria-label="Kembali">
          <IoArrowBack />
        </button>
        <div className="seg cp-tabs">
          <button className={mode === 'text' ? 'active' : ''} onClick={() => setMode('text')}>
            <IoTextOutline /> Teks
          </button>
          <button className={mode === 'media' ? 'active' : ''} onClick={() => setMode('media')}>
            <IoImageOutline /> Media
          </button>
        </div>
        <div style={{ width: 44 }} />
      </div>

      {mode === 'text' ? (
        <div className="cp-body" style={{ background: bg }}>
          <textarea
            className="cp-textarea"
            placeholder="Ketik status…"
            value={text}
            maxLength={500}
            onChange={(e) => setText(e.target.value)}
            autoFocus
          />
        </div>
      ) : (
        <div className="cp-body cp-media">
          <input ref={fileRef} type="file" accept="image/*,video/*" hidden onChange={postMedia} />
          <button className="cp-pick" onClick={() => fileRef.current?.click()} disabled={busy}>
            <IoImageOutline />
            <span>{busy ? 'Mengunggah…' : 'Pilih Foto / Video'}</span>
          </button>
          <p className="muted">Status hilang otomatis setelah 24 jam.</p>
        </div>
      )}

      {mode === 'text' && (
        <div className="cp-footer">
          <div className="color-row">
            {STATUS_COLORS.map((c) => (
              <button
                key={c}
                className={`color-dot${bg === c ? ' active' : ''}`}
                style={{ background: c }}
                onClick={() => setBg(c)}
                aria-label={c}
              />
            ))}
          </div>
          <button className="send-btn cp-send" onClick={postText} disabled={busy || !text.trim()} aria-label="Kirim">
            <IoSend />
          </button>
        </div>
      )}

      {error && <div className="auth-error cp-error">{error}</div>}
    </div>
  )
}
