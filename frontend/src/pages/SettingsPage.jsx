import { useApp } from '../context/AppContext'
import SettingsView from '../components/SettingsView'

export default function SettingsPage() {
  const { session, logout } = useApp()
  return (
    <SettingsView token={session.token} me={session.username} onLogout={logout} />
  )
}
