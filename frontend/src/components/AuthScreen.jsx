import { useState } from 'react'
import { FaTelegramPlane } from 'react-icons/fa'
import { api } from '../api'

/* Login / register screen */
export default function AuthScreen({ onAuth }) {
  const [mode, setMode] = useState('login') // 'login' | 'register'
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    setError('')
    setBusy(true)
    try {
      const fn = mode === 'login' ? api.login : api.register
      const data = await fn(username.trim(), password)
      onAuth({ token: data.token, username: data.username })
    } catch (err) {
      setError(friendly(err.message))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="auth-wrap">
      <div className="auth-card">
        <div className="auth-logo">
          <FaTelegramPlane />
        </div>
        <h1>Telegram Clone</h1>
        <p className="auth-sub">
          {mode === 'login'
            ? 'Selamat datang kembali'
            : 'Buat akun untuk mulai chatting'}
        </p>
        <form onSubmit={submit}>
          <input
            className="input"
            placeholder="Username"
            value={username}
            onChange={(e) => setUsername(e.target.value)}
            autoFocus
          />
          <input
            className="input"
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
          {error && <div className="auth-error">{error}</div>}
          <button className="btn-primary btn-block" disabled={busy}>
            {busy ? '…' : mode === 'login' ? 'Masuk' : 'Daftar'}
          </button>
        </form>
        <button
          className="link-btn"
          onClick={() => {
            setMode(mode === 'login' ? 'register' : 'login')
            setError('')
          }}
        >
          {mode === 'login'
            ? 'Belum punya akun? Daftar'
            : 'Sudah punya akun? Masuk'}
        </button>
      </div>
    </div>
  )
}

function friendly(code) {
  switch (code) {
    case 'bad_credentials': return 'Username atau password salah.'
    case 'username_taken': return 'Username sudah dipakai.'
    case 'invalid_input': return 'Username min. 3 karakter, password min. 4 karakter.'
    default: return 'Terjadi kesalahan. Coba lagi.'
  }
}
