import { useEffect, useState } from 'react'

interface HealthData {
  status: string
  db: string
  version: string
}

export default function App() {
  const [health, setHealth] = useState<HealthData | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch('/api/health')
      .then((res) => {
        if (!res.ok) {
          throw new Error(`HTTP ${res.status}`)
        }
        return res.json()
      })
      .then((data: HealthData) => setHealth(data))
      .catch((err: Error) => setError(err.message))
  }, [])

  return (
    <div className="min-h-screen flex flex-col items-center justify-center p-6 bg-stone-50 text-stone-900">
      <main className="w-full max-w-md bg-white border border-stone-200 rounded-xl p-8 shadow-sm">
        <header className="mb-6">
          <h1 className="text-2xl font-semibold tracking-tight">Ledger</h1>
          <p className="text-sm text-stone-500 mt-1">轻量个性化记账 · 工程脚手架</p>
        </header>

        <section className="space-y-4">
          <div className="flex items-center justify-between py-2 border-b border-stone-100 text-sm">
            <span className="text-stone-500">服务状态</span>
            <span className="inline-flex items-center gap-1.5 font-medium">
              <span
                className={`w-2 h-2 rounded-full ${
                  health?.status === 'ok'
                    ? 'bg-emerald-500'
                    : error
                    ? 'bg-rose-500'
                    : 'bg-amber-500 animate-pulse'
                }`}
              />
              {health ? health.status : error ? '离线' : '检测中...'}
            </span>
          </div>

          <div className="flex items-center justify-between py-2 border-b border-stone-100 text-sm">
            <span className="text-stone-500">数据库</span>
            <span className="font-mono text-xs text-stone-700">
              {health ? health.db : error ? error : '-'}
            </span>
          </div>

          <div className="flex items-center justify-between py-2 border-b border-stone-100 text-sm">
            <span className="text-stone-500">技术栈</span>
            <span className="text-xs text-stone-600">
              Go · React · Vite · Tailwind · SQLite
            </span>
          </div>
        </section>
      </main>
    </div>
  )
}
