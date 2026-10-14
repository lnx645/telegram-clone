import { IoSearch, IoPeopleOutline, IoAdd } from 'react-icons/io5'
import { avatarColor, initials, fmtTime } from '../utils'

/* Chat list (direct + groups) with inline search */
export default function ChatList({ chats, activeId, onSelect, me, onNewGroup }) {
  return (
    <div className="pane">
      <div className="list-header">
        <div className="search-box grow">
          <IoSearch className="search-icon" />
          <input
            className="input search-input"
            placeholder="Cari chat…"
            onChange={(e) => {
              const q = e.target.value.toLowerCase()
              document.querySelectorAll('.chat-item').forEach((el) => {
                el.style.display = el.dataset.search.includes(q) ? '' : 'none'
              })
            }}
          />
        </div>
        <button className="icon-btn" onClick={onNewGroup} aria-label="Grup baru" title="Grup baru">
          <IoAdd />
        </button>
      </div>
      <div className="chat-list">
        {chats.length === 0 && (
          <div className="empty">
            Belum ada chat.<br />
            Buka tab Kontak atau buat grup baru.
          </div>
        )}
        {chats.map((c) => {
          const isGroup = c.type === 'group'
          const title = isGroup ? c.name : c.peer
          return (
            <button
              key={c.id}
              data-search={(title || '').toLowerCase()}
              className={`chat-item${c.id === activeId ? ' active' : ''}`}
              onClick={() => onSelect(c.id)}
            >
              <div className="avatar sm" style={{ background: avatarColor(title || '?') }}>
                {isGroup ? <IoPeopleOutline /> : initials(c.peer)}
              </div>
              <div className="chat-meta">
                <strong>{title}</strong>
                <span className="preview">
                  {c.last_message ? preview(c.last_message, me) : (
                    isGroup ? `${c.member_count} anggota` : 'Belum ada pesan'
                  )}
                </span>
              </div>
              <span className="time">
                {c.last_message ? fmtTime(c.last_message.ts) : ''}
              </span>
            </button>
          )
        })}
      </div>
    </div>
  )
}

function preview(m, me) {
  const who = m.from === me ? 'Anda: ' : `${m.from}: `
  if (m.kind === 'sticker') return `${who}Stiker`
  if (m.kind === 'image') return `${who}${m.text || 'Foto'}`
  if (m.kind === 'video') return `${who}${m.text || 'Video'}`
  if (m.kind === 'voice') return `${who}Pesan suara`
  const t = who + (m.text || '')
  return t.length > 36 ? t.slice(0, 36) + '…' : t
}
