import { useEffect, useRef, useState } from 'react'
import {
  IoArrowBack,
  IoSend,
  IoCheckmark,
  IoCheckmarkDone,
  IoAttachOutline,
  IoHappyOutline,
  IoClose,
  IoMicOutline,
  IoTrashOutline,
  IoReturnUpBackOutline,
  IoInformationCircleOutline,
} from 'react-icons/io5'
import { api, presenceLabel, REACTION_EMOJIS } from '../api'
import { avatarColor, initials, fmtTime } from '../utils'
import StickerPicker from './StickerPicker'

/* Message thread: ticks, typing, reply, reactions, delete, voice, video */
export default function ChatView({
  token, me, chat, extra, event, onSent, onBack, onTyping, typingFrom, onGroupInfo,
}) {
  const [messages, setMessages] = useState([])
  const [draft, setDraft] = useState('')
  const [loading, setLoading] = useState(false)
  const [showStickers, setShowStickers] = useState(false)
  const [uploading, setUploading] = useState(false)
  const [replyTo, setReplyTo] = useState(null)
  const [reactTo, setReactTo] = useState(null) // msg id with open emoji picker
  const [menuFor, setMenuFor] = useState(null) // msg id with open action menu
  const [recording, setRecording] = useState(false)
  const [recSecs, setRecSecs] = useState(0)
  const bottomRef = useRef(null)
  const fileRef = useRef(null)
  const mediaRef = useRef(null)
  const typingTimer = useRef(null)
  const recRef = useRef(null)
  const recTimer = useRef(null)

  const chatId = chat?.id

  useEffect(() => {
    if (!chat) return
    setLoading(true)
    setShowStickers(false)
    setReplyTo(null)
    setMenuFor(null)
    setReactTo(null)
    api.listMessages(token, chat.id)
      .then((d) => setMessages(d.messages))
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [chatId]) // eslint-disable-line

  useEffect(() => {
    if (!extra || !chat || extra.chat_id !== chat.id) return
    setMessages((ms) =>
      ms.some((m) => m.id === extra.id) ? ms : [...ms, extra]
    )
    // Auto mark as read while the chat is open.
    api.markRead(token, chat.id).catch(() => {})
  }, [extra, chatId]) // eslint-disable-line

  // Refresh on reaction/deletion events for this chat.
  useEffect(() => {
    if (!event || !chat || event.chat_id !== chat.id) return
    if (event.type === 'reaction' || event.type === 'message_deleted') {
      api.listMessages(token, chat.id)
        .then((d) => setMessages(d.messages))
        .catch(() => {})
    }
  }, [event, chatId]) // eslint-disable-line

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  if (!chat) {
    return (
      <section className="chat-view chat-empty">
        <div className="chat-empty-inner">
          <div className="big-icon"><IoSend /></div>
          <h2>Pilih chat untuk mulai</h2>
          <p>Buka tab Kontak untuk mencari teman.</p>
        </div>
      </section>
    )
  }

  const isGroup = chat.type === 'group'
  const title = isGroup ? chat.name : chat.peer
  const subtitle = typingFrom
    ? `${typingFrom} sedang mengetik…`
    : isGroup
      ? `${chat.member_count} anggota`
      : presenceLabel(chat.peer_presence)

  const push = (msg) => {
    setMessages((ms) => [...ms, msg])
    onSent?.(chat.id, msg)
  }

  const sendPayload = async (payload) => {
    try {
      const data = await api.send(token, chat.id, {
        ...payload,
        reply_to: replyTo?.id,
      })
      setReplyTo(null)
      push(data.message)
    } catch { /* ignore */ }
  }

  const sendText = (e) => {
    e.preventDefault()
    const text = draft.trim()
    if (!text) return
    setDraft('')
    sendPayload({ kind: 'text', text })
  }

  const onInput = (e) => {
    setDraft(e.target.value)
    onTyping?.(chat.id)
  }

  const sendSticker = (url) => sendPayload({ kind: 'sticker', media_url: url })

  const uploadAndSend = async (file, kind) => {
    if (!file) return
    setUploading(true)
    try {
      const url = await api.uploadMedia(token, file)
      await sendPayload({ kind, media_url: url, text: '' })
    } catch { /* ignore */ }
    finally { setUploading(false) }
  }

  const onPickFile = (e) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    const kind = file.type.startsWith('image/') ? 'image'
      : file.type.startsWith('video/') ? 'video' : null
    if (!kind) return
    uploadAndSend(file, kind)
  }

  /* ---- voice notes ---- */
  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true })
      const rec = new MediaRecorder(stream)
      const chunks = []
      rec.ondataavailable = (e) => chunks.push(e.data)
      rec.onstop = async () => {
        stream.getTracks().forEach((t) => t.stop())
        const blob = new Blob(chunks, { type: rec.mimeType || 'audio/webm' })
        const file = new File([blob], `voice-${Date.now()}.webm`, { type: blob.type })
        uploadAndSend(file, 'voice')
      }
      recRef.current = rec
      rec.start()
      setRecording(true)
      setRecSecs(0)
      recTimer.current = setInterval(() => setRecSecs((s) => s + 1), 1000)
    } catch { /* mic denied */ }
  }

  const stopRecording = (send = true) => {
    clearInterval(recTimer.current)
    setRecording(false)
    const rec = recRef.current
    recRef.current = null
    if (rec && rec.state !== 'inactive') {
      if (!send) rec.onstop = () => {}
      rec.stop()
    }
  }

  /* ---- message actions ---- */
  const doReact = async (msg, emoji) => {
    setReactTo(null)
    try {
      const existing = msg.reactions?.find((r) => r.by_me)
      if (existing && existing.emoji === emoji) {
        await api.removeReaction(token, msg.id)
      } else {
        await api.addReaction(token, msg.id, emoji)
      }
      const d = await api.listMessages(token, chat.id)
      setMessages(d.messages)
    } catch { /* ignore */ }
  }

  const doDelete = async (msg, mode) => {
    setMenuFor(null)
    try {
      await api.deleteMessage(token, chat.id, msg.id, mode)
      if (mode === 'me') {
        setMessages((ms) => ms.filter((m) => m.id !== msg.id))
      } else {
        const d = await api.listMessages(token, chat.id)
        setMessages(d.messages)
      }
    } catch { /* ignore */ }
  }

  const header = (
    <div className="chat-header">
      <button className="back-btn" onClick={onBack} aria-label="Kembali">
        <IoArrowBack />
      </button>
      <div className="avatar sm" style={{ background: avatarColor(title || '?') }}>
        {initials(title || '?')}
      </div>
      <div className="min-w-0">
        <strong>{title}</strong>
        <div className={`online${typingFrom ? ' typing' : ''}`}>{subtitle}</div>
      </div>
      <div style={{ flex: 1 }} />
      {isGroup && (
        <button className="icon-btn sm" onClick={() => onGroupInfo?.()} aria-label="Info grup">
          <IoInformationCircleOutline />
        </button>
      )}
    </div>
  )

  return (
    <section className="chat-view">
      {header}

      <div className="messages" onClick={() => { setMenuFor(null); setReactTo(null) }}>
        {loading && <div className="empty">Memuat…</div>}
        {messages.map((m) => (
          <MessageBubble
            key={m.id}
            m={m}
            me={me}
            isGroup={isGroup}
            menuOpen={menuFor === m.id}
            reactOpen={reactTo === m.id}
            onMenu={() => { setMenuFor(menuFor === m.id ? null : m.id); setReactTo(null) }}
            onReactOpen={() => { setReactTo(reactTo === m.id ? null : m.id); setMenuFor(null) }}
            onReact={(emoji) => doReact(m, emoji)}
            onReply={() => { setReplyTo(m); setMenuFor(null) }}
            onDelete={(mode) => doDelete(m, mode)}
          />
        ))}
        <div ref={bottomRef} />
      </div>

      {replyTo && (
        <div className="reply-bar">
          <div className="reply-quote">
            <strong>{replyTo.from === me ? 'Anda' : replyTo.from}</strong>
            <span>{replyText(replyTo)}</span>
          </div>
          <button className="icon-btn sm" onClick={() => setReplyTo(null)} aria-label="Batal">
            <IoClose />
          </button>
        </div>
      )}

      {showStickers && (
        <StickerPicker onPick={sendSticker} onClose={() => setShowStickers(false)} />
      )}

      <form className="composer" onSubmit={sendText}>
        {recording ? (
          <div className="recording-bar">
            <span className="rec-dot" />
            <span>{fmtSecs(recSecs)} — merekam…</span>
            <button type="button" className="icon-btn sm" onClick={() => stopRecording(false)} aria-label="Batal">
              <IoTrashOutline />
            </button>
            <button type="button" className="btn-primary btn-sm" onClick={() => stopRecording(true)}>
              Kirim
            </button>
          </div>
        ) : (
          <>
            <button type="button" className="icon-btn" aria-label="Lampirkan"
              onClick={() => fileRef.current?.click()} disabled={uploading}>
              <IoAttachOutline />
            </button>
            <button type="button" className={`icon-btn${showStickers ? ' active' : ''}`}
              aria-label="Stiker" onClick={() => setShowStickers((s) => !s)}>
              {showStickers ? <IoClose /> : <IoHappyOutline />}
            </button>
            <input ref={fileRef} type="file" accept="image/*,video/*" hidden onChange={onPickFile} />
            <input
              className="input"
              placeholder={uploading ? 'Mengunggah…' : 'Tulis pesan…'}
              value={draft}
              onChange={onInput}
              disabled={uploading}
            />
            {draft.trim() ? (
              <button className="send-btn" type="submit" aria-label="Kirim">
                <IoSend />
              </button>
            ) : (
              <button type="button" className="send-btn" aria-label="Pesan suara"
                onClick={startRecording} disabled={uploading}>
                <IoMicOutline />
              </button>
            )}
          </>
        )}
      </form>
    </section>
  )
}

/* ---------- single message bubble ---------- */
function MessageBubble({ m, me, isGroup, menuOpen, reactOpen, onMenu, onReactOpen, onReact, onReply, onDelete }) {
  const mine = m.from === me
  const longPress = useRef(null)

  const startPress = () => {
    longPress.current = setTimeout(onReactOpen, 450)
  }
  const endPress = () => clearTimeout(longPress.current)

  if (m.kind === 'sticker') {
    return (
      <div className={`bubble-row${mine ? ' mine' : ''}`}>
        <div className="sticker-wrap"
          onContextMenu={(e) => { e.preventDefault(); onMenu() }}
          onTouchStart={startPress} onTouchEnd={endPress}>
          <img src={m.media_url} className="sticker-msg" alt="stiker" />
          <ReactionBadges m={m} me={me} />
        </div>
        <MsgMenu m={m} mine={mine} open={menuOpen}
          onReactOpen={onReactOpen} onReply={onReply} onDelete={onDelete} />
        {reactOpen && <EmojiPicker onPick={onReact} />}
      </div>
    )
  }

  return (
    <div className={`bubble-row${mine ? ' mine' : ''}`}>
      <div className="bubble"
        onContextMenu={(e) => { e.preventDefault(); onMenu() }}
        onTouchStart={startPress} onTouchEnd={endPress}>
        {isGroup && !mine && <div className="bubble-sender">{m.from}</div>}
        {m.reply_to && (
          <div className="quote">
            <strong>{m.reply_to.from === me ? 'Anda' : m.reply_to.from}</strong>
            <span>{m.reply_to.text}</span>
          </div>
        )}
        {m.kind === 'image' && m.media_url && (
          <img src={m.media_url} className="msg-img" alt="" loading="lazy" />
        )}
        {m.kind === 'video' && m.media_url && (
          <video src={m.media_url} className="msg-img" controls preload="metadata" />
        )}
        {m.kind === 'voice' && m.media_url && (
          <audio src={m.media_url} className="msg-audio" controls preload="metadata" />
        )}
        {!!m.text && <div className="bubble-text">{m.text}</div>}
        <div className="bubble-meta">
          <span>{fmtTime(m.ts)}</span>
          {mine && <Ticks status={m.status} />}
        </div>
        <ReactionBadges m={m} me={me} />
      </div>
      <MsgMenu m={m} mine={mine} open={menuOpen}
        onReactOpen={onReactOpen} onReply={onReply} onDelete={onDelete} />
      {reactOpen && <EmojiPicker onPick={onReact} />}
    </div>
  )
}

/* WhatsApp-style ticks */
function Ticks({ status }) {
  if (status === 'read')
    return <IoCheckmarkDone className="tick read" />
  if (status === 'delivered')
    return <IoCheckmarkDone className="tick" />
  return <IoCheckmark className="tick" />
}

function ReactionBadges({ m }) {
  if (!m.reactions || m.reactions.length === 0) return null
  return (
    <div className="reaction-badges">
      {m.reactions.map((r) => (
        <span key={r.emoji} className={`rbadge${r.by_me ? ' mine' : ''}`}>
          {r.emoji}{r.count > 1 ? ` ${r.count}` : ''}
        </span>
      ))}
    </div>
  )
}

function EmojiPicker({ onPick }) {
  return (
    <div className="emoji-picker">
      {REACTION_EMOJIS.map((e) => (
        <button key={e} className="emoji-btn" onClick={() => onPick(e)}>{e}</button>
      ))}
    </div>
  )
}

function MsgMenu({ m, mine, open, onReactOpen, onReply, onDelete }) {
  if (!open) return null
  return (
    <div className={`msg-menu${mine ? ' mine' : ''}`} onClick={(e) => e.stopPropagation()}>
      <button onClick={onReactOpen}><IoHappyOutline /> Reaksi</button>
      <button onClick={onReply}><IoReturnUpBackOutline /> Balas</button>
      <button onClick={() => onDelete('me')}><IoTrashOutline /> Hapus untuk saya</button>
      {mine && (
        <button className="danger-text" onClick={() => onDelete('everyone')}>
          <IoTrashOutline /> Hapus untuk semua
        </button>
      )}
    </div>
  )
}

function replyText(m) {
  if (m.kind === 'sticker') return 'Stiker'
  if (m.kind === 'image') return m.text || 'Foto'
  if (m.kind === 'video') return m.text || 'Video'
  if (m.kind === 'voice') return 'Pesan suara'
  return (m.text || '').slice(0, 60)
}

function fmtSecs(s) {
  const mm = String(Math.floor(s / 60)).padStart(2, '0')
  const ss = String(s % 60).padStart(2, '0')
  return `${mm}:${ss}`
}
