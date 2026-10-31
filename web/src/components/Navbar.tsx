import type { FC } from 'react';
import {
  BrandIcon,
  StreamIcon,
  StatsIcon,
  SubscriptionIcon,
  WalletIcon,
  SettingsIcon,
  MoonIcon,
  SunIcon,
  LogoutIcon,
} from './Icons';
import { SegmentedControl, IconButton } from './primitives';
import type { SegmentedItem } from './primitives';

export type TabType = 'stream' | 'stats' | 'subscriptions' | 'assets' | 'settings';

const TAB_ITEMS: SegmentedItem[] = [
  { key: 'stream', label: '流水', icon: <StreamIcon size={15} /> },
  { key: 'stats', label: '统计', icon: <StatsIcon size={15} /> },
  { key: 'subscriptions', label: '订阅', icon: <SubscriptionIcon size={15} /> },
  { key: 'assets', label: '资产', icon: <WalletIcon size={15} /> },
  { key: 'settings', label: '设置', icon: <SettingsIcon size={15} /> },
];

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
}) => (
  <header
    className="sticky top-0 z-50 h-[60px] flex items-center justify-between gap-3 px-3 min-[640px]:px-6
      bg-[var(--glass)] backdrop-blur-[18px] saturate-150
      border-b border-[var(--line)] shadow-[inset_0_-1px_0_var(--highlight-top)]"
  >
    {/* Brand */}
    <div className="flex items-center gap-2.5 min-w-0">
      <div
        className="w-[30px] h-[30px] rounded-[var(--r-sm)] flex items-center justify-center text-white flex-shrink-0
          bg-[linear-gradient(160deg,var(--brand),var(--brand-pressed))]
          shadow-[0_2px_6px_var(--brand-glow),inset_0_1px_0_rgba(255,255,255,.25)]"
      >
        <BrandIcon size={16} />
      </div>
      <span className="hidden min-[400px]:inline text-base font-[650] tracking-[-.015em] text-[var(--fg)] whitespace-nowrap">
        Ledger
      </span>
    </div>

    {/* Segmented Navigation */}
    <nav>
      <SegmentedControl
        items={TAB_ITEMS}
        value={currentTab}
        onChange={(key) => onTabChange(key as TabType)}
        ariaLabel="主导航"
        compact
        className="[&>button]:px-[7px] min-[420px]:[&>button]:px-2.5"
      />
    </nav>

    {/* Action Cluster */}
    <div className="flex items-center gap-1">
      <IconButton
        label={darkMode ? '切换浅色模式' : '切换暗黑模式'}
        onClick={onToggleDarkMode}
      >
        {darkMode ? <SunIcon size={16} /> : <MoonIcon size={16} />}
      </IconButton>

      <div
        className="hidden min-[768px]:flex items-center gap-2 py-1 pl-1 pr-2.5
          bg-[var(--surface-sunken)] border border-[var(--line)] rounded-[var(--r-pill)]
          text-[12.5px] text-[var(--fg-2)] select-none"
      >
        <div className="w-[22px] h-[22px] rounded-full bg-[var(--brand)] text-white text-[11px] font-bold flex items-center justify-center">
          A
        </div>
        <span>admin</span>
      </div>

      <IconButton label="退出登录" tone="danger" onClick={onLogout}>
        <LogoutIcon size={15} />
      </IconButton>
    </div>
  </header>
);
