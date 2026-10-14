import { NavLink, Routes, Route, useLocation } from 'react-router-dom'
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
import ChatsPage from '../pages/ChatsPage'
import ChatPage from '../pages/ChatPage'
import StatusPage from '../pages/StatusPage'
import StatusComposePage from '../pages/StatusComposePage'
import StatusViewerPage from '../pages/StatusViewerPage'
import ContactsPage from '../pages/ContactsPage'
import SettingsPage from '../pages/SettingsPage'
import NewGroupPage from '../pages/NewGroupPage'
import GroupInfoPage from '../pages/GroupInfoPage'
import ChatEmpty from '../components/ChatEmpty'

const TABS = [
  { to: '/chats', label: 'Chat', Icon: IoChatbubbles, IconOff: IoChatbubblesOutline },
  { to: '/status', label: 'Status', Icon: IoAtCircle, IconOff: IoAtCircleOutline },
  { to: '/contacts', label: 'Kontak', Icon: IoPeople, IconOff: IoPeopleOutline },
  { to: '/settings', label: 'Setting', Icon: IoSettings, IconOff: IoSettingsOutline },
]

function TabRail() {
  return (
    <nav className="tab-rail">
      {TABS.map(({ to, label, Icon, IconOff }) => (
        <NavLink
          key={to}
          to={to}
          className={({ isActive }) => `rail-btn${isActive ? ' active' : ''}`}
          title={label}
        >
          {({ isActive }) => (isActive ? <Icon /> : <IconOff />)}
        </NavLink>
      ))}
    </nav>
  )
}

function BottomNav() {
  return (
    <nav className="bottom-nav">
      {TABS.map(({ to, label, Icon, IconOff }) => (
        <NavLink
          key={to}
          to={to}
          className={({ isActive }) => `tab-btn${isActive ? ' active' : ''}`}
        >
          {({ isActive }) => (
            <>
              {isActive ? <Icon /> : <IconOff />}
              <span>{label}</span>
            </>
          )}
        </NavLink>
      ))}
    </nav>
  )
}

/* Main app shell with React Router */
export default function Shell() {
  const location = useLocation()
  const path = location.pathname

  const isChats = path.startsWith('/chats')
  const inChatDetail = /^\/chats\/\d+/.test(path)
  const isFullscreen = path.startsWith('/status/compose') ||
    path.startsWith('/status/view')

  if (isFullscreen) {
    return (
      <div className="app">
        <Routes>
          <Route path="/status/compose" element={<StatusComposePage />} />
          <Route path="/status/view/:username" element={<StatusViewerPage />} />
        </Routes>
      </div>
    )
  }

  return (
    <div className={`app${inChatDetail ? ' chat-open' : ''}`}>
      <TabRail />

      {isChats ? (
        <>
          <aside className="panel-list">
            <ChatsPage />
          </aside>
          <main className="panel-detail">
            <Routes>
              <Route path="/chats" element={<ChatEmpty />} />
              <Route path="/chats/:id" element={<ChatPage />} />
            </Routes>
          </main>
        </>
      ) : (
        <main className="panel-content">
          <Routes>
            <Route path="/status" element={<StatusPage />} />
            <Route path="/contacts" element={<ContactsPage />} />
            <Route path="/settings" element={<SettingsPage />} />
            <Route path="/group/new" element={<NewGroupPage />} />
            <Route path="/group/:id" element={<GroupInfoPage />} />
          </Routes>
        </main>
      )}

      <BottomNav />
    </div>
  )
}
