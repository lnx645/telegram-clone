import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import StatusViewer from '../components/StatusViewer'

/* Fullscreen status viewer (route: /status/view/:username) */
export default function StatusViewerPage() {
  const { username } = useParams()
  const location = useLocation()
  const navigate = useNavigate()
  const { session, bumpStatusKey } = useApp()

  const statuses = location.state?.statuses || []

  const close = () => {
    bumpStatusKey()
    navigate('/status')
  }

  return (
    <StatusViewer
      token={session.token}
      me={session.username}
      username={username}
      statuses={statuses}
      onClose={close}
      onDone={close}
    />
  )
}
