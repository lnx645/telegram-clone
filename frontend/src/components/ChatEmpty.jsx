import { IoChatbubblesOutline } from 'react-icons/io5'

export default function ChatEmpty() {
  return (
    <div className="chat-empty">
      <IoChatbubblesOutline />
      <h2>Pilih chat untuk mulai</h2>
      <p>Percakapanmu akan muncul di sini.</p>
    </div>
  )
}
