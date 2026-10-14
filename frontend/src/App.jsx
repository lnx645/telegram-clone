import { BrowserRouter, Routes, Route, Navigate, useNavigate } from 'react-router-dom'
import { AppProvider, useApp } from './context/AppContext'
import AuthScreen from './components/AuthScreen'
import Shell from './components/Shell'
import './App.css'

function RequireAuth({ children }) {
  const { session } = useApp()
  if (!session) return <Navigate to="/login" replace />
  return children
}

function LoginPage() {
  const { session, login } = useApp()
  const navigate = useNavigate()
  if (session) return <Navigate to="/chats" replace />
  return (
    <AuthScreen
      onAuth={(s) => {
        login(s)
        navigate('/chats', { replace: true })
      }}
    />
  )
}

export default function App() {
  return (
    <BrowserRouter>
      <AppProvider>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route
            path="/*"
            element={
              <RequireAuth>
                <Shell />
              </RequireAuth>
            }
          />
        </Routes>
      </AppProvider>
    </BrowserRouter>
  )
}
