import { useState } from 'react';
import type { FC, FormEvent } from 'react';
import { LockIcon } from './Icons';
import { api } from '../lib/api';

interface AuthModalProps {
  isOpen: boolean;
  onSuccess: () => void;
}

export const AuthModal: FC<AuthModalProps> = ({ isOpen, onSuccess }) => {
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!password.trim()) {
      setError('请输入管理员密码');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      await api.login(password);
      setPassword('');
      onSuccess();
    } catch (err: any) {
      setError(err?.message || '密码错误，请重试');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[1000] bg-black/45 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="w-full max-w-sm bg-[var(--color-card-bg)] rounded-2xl shadow-[var(--shadow-modal)] border border-[var(--color-neutral-stroke)] p-6 flex flex-col gap-5 animate-fade-in">
        <div className="flex flex-col items-center text-center gap-2">
          <div className="w-12 h-12 rounded-xl bg-[var(--color-brand-light)] text-[var(--color-brand)] flex items-center justify-center mb-1">
            <LockIcon size={24} />
          </div>
          <h2 className="text-lg font-semibold text-[var(--color-neutral-fg-1)]">
            管理员安全解锁
          </h2>
          <p className="text-xs text-[var(--color-neutral-fg-3)] leading-relaxed">
            Ledger 处于安全保护状态，请输入管理员密码以继续
          </p>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">
              管理密码
            </label>
            <input
              type="password"
              autoFocus
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="请输入管理员密码"
              className="w-full px-3.5 py-2 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke-strong)] text-sm text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)] focus:bg-[var(--color-card-bg)] transition-colors"
            />
          </div>

          {error && (
            <div className="text-xs text-[var(--color-expense-dark)] bg-[var(--color-expense-bg)] px-3 py-2 rounded-lg border border-[var(--color-expense-stroke)]">
              {error}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full py-2.5 rounded-lg bg-[var(--color-brand)] hover:bg-[var(--color-brand-hover)] text-white text-sm font-semibold cursor-pointer disabled:opacity-50 transition-colors shadow-[0_2px_8px_rgba(0,120,212,0.3)]"
          >
            {loading ? '验证中...' : '确认解锁'}
          </button>
        </form>
      </div>
    </div>
  );
};
