import { useRef, useState } from 'react'
import { IoClose, IoImageOutline, IoTextOutline } from 'react-icons/io5'
import { api, STATUS_COLORS } from '../api'

/* Post a new status: text or photo/video */
export default function NewStatusModal({ token, onClose, onPosted }) {
  const [mode, setMode] = useState('text') // text | media
  const [text, setText] = useState('')
  const [bg, setBg] = useState(STATUS_COLORS[0])
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const fileRef = useRef(null)

  const postText = async () => {
    if (!text.trim()) { setError('Tulis sesuatu dulu.'); return }
    setBusy(true); setError('')
    try {
      await api.postStatus(token, { kind: 'text', text: text.trim(), bg_color: bg })
      onPosted()
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
      const url = await api.uploadMedia(token, file)
      await api.postStatus(token, { kind, media_url: url })
      onPosted()
    } catch {
      setError('Gagal mengunggah.')
    } finally { setBusy(false) }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h3>Status Baru</h3>
          <button className="icon-btn sm" onClick={onClose} aria-label="Tutup">
            <IoClose />
          </button>
        </div>

        <div className="seg">
          <button className={mode === 'text' ? 'active' : ''} onClick={() => setMode('text')}>
            <IoTextOutline /> Teks
          </button>
          <button className={mode === 'media' ? 'active' : ''} onClick={() => setMode('media')}>
            <IoImageOutline /> Foto/Video
          </button>
        </div>

        {mode === 'text' ? (
          <>
            <div className="status-preview" style={{ background: bg }}>
              {text || 'Tulis statusmu…'}
            </div>
            <textarea
              className="input"
              rows={3}
              maxLength={500}
              placeholder="Tulis status…"
              value={text}
              onChange={(e) => setText(e.target.value)}
              autoFocus
            />
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
            <button className="btn-primary btn-block" onClick={postText} disabled={busy}>
              {busy ? 'Memposting…' : 'Posting'}
            </button>
          </>
        ) : (
          <>
            <input ref={fileRef} type="file" accept="image/*,video/*" hidden onChange={postMedia} />
            <button className="btn-primary btn-block" onClick={() => fileRef.current?.click()} disabled={busy}>
              {busy ? 'Mengunggah…' : 'Pilih Foto/Video'}
            </button>
            <p className="muted" style={{ textAlign: 'center' }}>
              Status hilang otomatis setelah 24 jam.
            </p>
          </>
        )}
        {error && <div className="auth-error">{error}</div>}
      </div>
    </div>
  )
}
