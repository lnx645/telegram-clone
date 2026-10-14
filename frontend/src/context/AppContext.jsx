import { createContext, useCallback, useContext, useEffect, useRef, useState } from 'react'
import { api, wsUrl } from '../api'

const LS_KEY = 'tc_session'

function loadSession() {
  try { return JSON.parse(localStorage.getItem(LS_KEY)) } catch { return null }
}

const AppContext = createContext(null)

/* Global in-memory state: session, chats, websocket, realtime events.
   Replaces prop-drilling with a single professional store. */
export function AppProvider({ children }) {
  const [session, setSession] = useState(loadSession)
  const [chats, setChats] = useState([])
  const [typingMap, setTypingMap] = useState({}) // chatId -> username
  const [wsEvent, setWsEvent] = useState(null) // last realtime event {type,...}
  const [incomingMsg, setIncomingMsg] = useState(null)
  const [contactsKey, setContactsKey] = useState(0)
  const [statusKey, setStatusKey] = useState(0)
  const wsRef = useRef(null)
  const typingTimeout = useRef({})
  const typingThrottle = useRef({})

  const refreshChats = useCallback(async () => {
    if (!session) return
    try {
      const data = await api.listChats(session.token)
      setChats(data.chats)
    } catch (err) {
      if (err.message === 'unauthorized' || err.message === 'http_401') {
        setSession(null)
        localStorage.removeItem(LS_KEY)
      }
    }
  }, [session])

  // Realtime websocket
  useEffect(() => {
    if (!session) return
    refreshChats()
    const ws = new WebSocket(wsUrl(session.token))
    wsRef.current = ws
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data)
        switch (data.type) {
          case 'message':
            setIncomingMsg(data.message)
            refreshChats()
            break
          case 'typing': {
            const key = data.chat_id
            setTypingMap((m) => ({ ...m, [key]: data.from }))
            clearTimeout(typingTimeout.current[key])
            typingTimeout.current[key] = setTimeout(() => {
              setTypingMap((m) => {
                const n = { ...m }
                delete n[key]
                return n
              })
            }, 2500)
            break
          }
          case 'receipt':
          case 'reaction':
          case 'message_deleted':
          case 'group_updated':
          case 'removed_from_group':
            setWsEvent(data)
            refreshChats()
            break
          case 'presence':
            setWsEvent(data)
            refreshChats()
            break
          case 'contact_request':
          case 'contact_accepted':
            setWsEvent(data)
            setContactsKey((k) => k + 1)
            break
          case 'new_status':
            setWsEvent(data)
            setStatusKey((k) => k + 1)
            break
          default:
            break
        }
      } catch { /* ignore */ }
    }
    return () => {
      ws.close()
      Object.values(typingTimeout.current).forEach(clearTimeout)
    }
  }, [session, refreshChats])

  const sendTyping = useCallback((chatId) => {
    const now = Date.now()
    if (now - (typingThrottle.current[chatId] || 0) < 2000) return
    typingThrottle.current[chatId] = now
    const ws = wsRef.current
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'typing', chat_id: chatId }))
    }
  }, [])

  const login = useCallback((s) => {
    localStorage.setItem(LS_KEY, JSON.stringify(s))
    setSession(s)
  }, [])

  const logout = useCallback(async () => {
    try { if (session) await api.logout(session.token) } catch { /* ignore */ }
    wsRef.current?.close()
    localStorage.removeItem(LS_KEY)
    setSession(null)
    setChats([])
    setTypingMap({})
  }, [session])

  const value = {
    session,
    chats,
    refreshChats,
    typingMap,
    wsEvent,
    incomingMsg,
    contactsKey,
    statusKey,
    bumpStatusKey: () => setStatusKey((k) => k + 1),
    sendTyping,
    login,
    logout,
  }

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>
}

export function useApp() {
  const ctx = useContext(AppContext)
  if (!ctx) throw new Error('useApp must be used within AppProvider')
  return ctx
}
