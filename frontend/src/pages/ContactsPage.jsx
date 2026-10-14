import { useNavigate } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import { api } from '../api'
import ContactsView from '../components/ContactsView'

export default function ContactsPage() {
  const { session, contactsKey, refreshChats } = useApp()
  const navigate = useNavigate()

  const openChat = async (username) => {
    const data = await api.openChat(session.token, username)
    await refreshChats()
    navigate(`/chats/${data.chat_id}`)
  }

  return (
    <div key={contactsKey} style={{ display: 'contents' }}>
      <ContactsView token={session.token} onOpen={openChat} />
    </div>
  )
}
