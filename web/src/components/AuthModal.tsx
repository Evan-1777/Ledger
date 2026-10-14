import { useState } from 'react';
import type { FC, FormEvent } from 'react';
import { LockIcon } from './Icons';
import { Button } from './primitives';
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
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : '密码错误，请重试');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[1000] bg-[rgba(8,12,20,.44)] backdrop-blur-[4px] flex items-center justify-center p-4 animate-fade">
      <div className="w-full max-w-sm bg-[var(--surface)] border border-[var(--line)] rounded-[var(--r-xl)] shadow-[var(--e4),inset_0_1px_0_var(--highlight-top)] p-6 flex flex-col gap-5 animate-pop">
        <div className="flex flex-col items-center text-center gap-2">
          <div className="w-12 h-12 rounded-[var(--r-md)] bg-[var(--brand-soft)] border border-[var(--brand-line)] text-[var(--brand-text)] flex items-center justify-center mb-1">
            <LockIcon size={22} />
          </div>
          <h2 className="text-lg font-semibold text-[var(--fg)]">管理员安全解锁</h2>
          <p className="text-xs text-[var(--fg-3)] leading-relaxed">
            Ledger 处于安全保护状态，请输入管理员密码以继续
          </p>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-xs font-semibold text-[var(--fg-2)]" htmlFor="auth-password">
              管理密码
            </label>
            <input
              id="auth-password"
              type="password"
              autoFocus
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="请输入管理员密码"
              className="w-full px-3 py-2 rounded-[var(--r-sm)] bg-[var(--surface)] border border-[var(--line-strong)]
                text-[13.5px] text-[var(--fg)] outline-none
                focus:border-[var(--brand)] focus:shadow-[0_0_0_3px_var(--brand-soft)]
                placeholder:text-[var(--fg-muted)]
                transition-[border-color,box-shadow] duration-[var(--d1)]"
            />
          </div>

          {error && (
            <div className="text-[12.5px] font-medium text-[var(--expense-text)] bg-[var(--expense-soft)] border border-[var(--expense-line)] px-3 py-2 rounded-[var(--r-sm)]">
              {error}
            </div>
          )}

          <Button type="submit" variant="primary" size="lg" disabled={loading} className="w-full">
            {loading ? '验证中…' : '确认解锁'}
          </Button>
        </form>
      </div>
    </div>
  );
};
