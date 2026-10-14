import {
  IoChatbubbles,
  IoChatbubblesOutline,
  IoPeople,
  IoPeopleOutline,
  IoSettings,
  IoSettingsOutline,
  IoAtCircle,
  IoAtCircleOutline,
} from 'react-icons/io5'

const TABS = [
  { id: 'chats', label: 'Chat', Icon: IoChatbubbles, IconOff: IoChatbubblesOutline },
  { id: 'status', label: 'Status', Icon: IoAtCircle, IconOff: IoAtCircleOutline },
  { id: 'contacts', label: 'Kontak', Icon: IoPeople, IconOff: IoPeopleOutline },
  { id: 'settings', label: 'Setting', Icon: IoSettings, IconOff: IoSettingsOutline },
]

/* Frosted-glass bottom navigation (mobile), like the real Telegram app */
export default function BottomNav({ tab, setTab }) {
  return (
    <nav className="bottom-nav">
      {TABS.map(({ id, label, Icon, IconOff }) => {
        const active = tab === id
        const I = active ? Icon : IconOff
        return (
          <button
            key={id}
            className={`tab-btn${active ? ' active' : ''}`}
            onClick={() => setTab(id)}
          >
            <I />
            <span>{label}</span>
          </button>
        )
      })}
    </nav>
  )
}
