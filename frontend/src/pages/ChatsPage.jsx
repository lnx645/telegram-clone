import { useNavigate } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import ChatList from '../components/ChatList'

export default function ChatsPage() {
  const { chats, session } = useApp()
  const navigate = useNavigate()

  return (
    <ChatList
      chats={chats}
      activeId={null}
      onSelect={(id) => navigate(`/chats/${id}`)}
      me={session.username}
      onNewGroup={() => navigate('/group/new')}
    />
  )
}
