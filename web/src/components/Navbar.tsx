import type { FC } from 'react';
import { BrandIcon, StreamIcon, StatsIcon, SettingsIcon, MoonIcon, SunIcon, LogoutIcon } from './Icons';

export type TabType = 'stream' | 'stats' | 'settings';

interface NavbarProps {
  currentTab: TabType;
  onTabChange: (tab: TabType) => void;
  darkMode: boolean;
  onToggleDarkMode: () => void;
  onLogout: () => void;
}

export const Navbar: FC<NavbarProps> = ({
  currentTab,
  onTabChange,
  darkMode,
  onToggleDarkMode,
  onLogout,
}) => {
  return (
    <header className="sticky top-0 z-50 h-[60px] bg-[var(--color-card-bg)] border-b border-[var(--color-neutral-stroke)] flex items-center justify-between px-8 transition-colors duration-200">
      {/* Left: Brand */}
      <div className="flex items-center gap-3">
        <div className="w-8 h-8 rounded-lg bg-[var(--color-brand)] flex items-center justify-center text-white shadow-[0_2px_6px_rgba(0,120,212,0.28)]">
          <BrandIcon size={18} />
        </div>
        <span className="text-lg font-semibold tracking-tight text-[var(--color-neutral-fg-1)]">
          Ledger
        </span>
      </div>

      {/* Center: Segmented Capsule Navigation */}
      <nav className="bg-[var(--color-canvas-bg)] rounded-full p-[3px] inline-flex items-center gap-1 border border-[var(--color-neutral-stroke)]">
        <button
          type="button"
          onClick={() => onTabChange('stream')}
          className={`flex items-center gap-1.5 px-4 py-1.5 rounded-full text-[13.5px] cursor-pointer transition-all duration-150 ${
            currentTab === 'stream'
              ? 'bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-1)] font-semibold shadow-[0_1px_4px_rgba(0,0,0,0.08)]'
              : 'text-[var(--color-neutral-fg-3)] font-medium hover:text-[var(--color-neutral-fg-1)]'
          }`}
        >
          <StreamIcon size={15} />
          <span>账目流水</span>
        </button>

        <button
          type="button"
          onClick={() => onTabChange('stats')}
          className={`flex items-center gap-1.5 px-4 py-1.5 rounded-full text-[13.5px] cursor-pointer transition-all duration-150 ${
            currentTab === 'stats'
              ? 'bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-1)] font-semibold shadow-[0_1px_4px_rgba(0,0,0,0.08)]'
              : 'text-[var(--color-neutral-fg-3)] font-medium hover:text-[var(--color-neutral-fg-1)]'
          }`}
        >
          <StatsIcon size={15} />
          <span>收支统计</span>
        </button>

        <button
          type="button"
          onClick={() => onTabChange('settings')}
          className={`flex items-center gap-1.5 px-4 py-1.5 rounded-full text-[13.5px] cursor-pointer transition-all duration-150 ${
            currentTab === 'settings'
              ? 'bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-1)] font-semibold shadow-[0_1px_4px_rgba(0,0,0,0.08)]'
              : 'text-[var(--color-neutral-fg-3)] font-medium hover:text-[var(--color-neutral-fg-1)]'
          }`}
        >
          <SettingsIcon size={15} />
          <span>基础设置</span>
        </button>
      </nav>

      {/* Right: Actions Cluster */}
      <div className="flex items-center gap-3">
        <button
          type="button"
          title={darkMode ? '切换浅色模式' : '切换暗黑模式'}
          onClick={onToggleDarkMode}
          className="w-[34px] h-[34px] rounded-lg border border-transparent flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:bg-[var(--color-hover-bg)] hover:text-[var(--color-neutral-fg-1)] hover:border-[var(--color-neutral-stroke)] cursor-pointer transition-all duration-150"
        >
          {darkMode ? <SunIcon size={16} /> : <MoonIcon size={16} />}
        </button>

        <div
          className="flex items-center gap-2 py-1 px-2.5 bg-[var(--color-hover-bg)] border border-[var(--color-neutral-stroke)] rounded-full text-[13px] text-[var(--color-neutral-fg-2)] select-none"
          title="管理员状态"
        >
          <div className="w-[22px] h-[22px] rounded-full bg-[var(--color-brand)] text-white text-[11px] font-bold flex items-center justify-center">
            A
          </div>
          <span>admin</span>
        </div>

        <button
          type="button"
          title="退出登录"
          onClick={onLogout}
          className="flex items-center gap-1.5 text-[13px] text-[var(--color-neutral-fg-3)] hover:text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] px-2.5 py-1.5 rounded-md cursor-pointer transition-all duration-150"
        >
          <LogoutIcon size={15} />
          <span>登出</span>
        </button>
      </div>
    </header>
  );
};
