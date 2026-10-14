import { STICKERS } from '../api'

/* Popup grid of stickers above the composer */
export default function StickerPicker({ onPick, onClose }) {
  return (
    <div className="sticker-picker">
      <div className="sticker-grid">
        {STICKERS.map((url) => (
          <button
            key={url}
            className="sticker-btn"
            onClick={() => { onPick(url); onClose?.() }}
          >
            <img src={url} alt="stiker" loading="lazy" />
          </button>
        ))}
      </div>
    </div>
  )
}
