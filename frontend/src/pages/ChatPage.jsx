import { useNavigate, useParams } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import ChatView from '../components/ChatView'

export default function ChatPage() {
  const { id } = useParams()
  const chatId = parseInt(id, 10)
  const navigate = useNavigate()
  const {
    session, chats, refreshChats, incomingMsg, wsEvent,
    sendTyping, typingMap,
  } = useApp()

  const chat = chats.find((c) => c.id === chatId) || null

  return (
    <ChatView
      token={session.token}
      me={session.username}
      chat={chat}
      extra={incomingMsg}
      event={wsEvent}
      onSent={refreshChats}
      onBack={() => navigate('/chats')}
      onTyping={sendTyping}
      typingFrom={typingMap[chatId]}
      onGroupInfo={() => navigate(`/group/${chatId}`)}
    />
  )
}
