import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import type { FC, FormEvent, ReactNode, RefObject } from 'react';
import { api } from '../lib/api';
import type { Subscription, SubscriptionGroup, SubscriptionInput } from '../lib/api';
import { formatMoney } from '../lib/format.ts';
import {
  Button,
  Chip,
  ConfirmDialog,
  EmptyState,
  IconButton,
  OverflowMenu,
  Panel,
  Skeleton,
} from '../components/primitives';
import type { OverflowMenuItem } from '../components/primitives';
import { AlertIcon, CloseIcon, PlusIcon } from '../components/Icons';
import { donutColor } from '../components/Charts';
import {
  buildSubscriptionSections,
  formatRenewalDate,
  nextRenewalDate,
  summarizeSubscriptions,
} from './subscriptionsUtils.ts';
import type { SubscriptionFilter, SubscriptionSection } from './subscriptionsUtils.ts';

type ToastFn = (type: 'success' | 'error' | 'info', message: string) => void;

interface SubscriptionsPageProps {
  authenticated: boolean;
  onToast: ToastFn;
}

interface SubscriptionDialogState {
  mode: 'create' | 'edit';
  subscription?: Subscription;
  defaultGroupId?: number | null;
}

interface GroupDialogState {
  mode: 'create' | 'rename';
  group?: SubscriptionGroup;
}

type PendingDelete =
  | { kind: 'subscription'; subscription: Subscription }
  | { kind: 'group'; group: SubscriptionGroup };

const FILTERS: { key: SubscriptionFilter; label: string }[] = [
  { key: 'all', label: '全部' },
  { key: 'active', label: '使用中' },
  { key: 'paused', label: '已暂停' },
];

const inputClass = (hasError: boolean) =>
  `w-full h-[38px] px-2.5 rounded-[var(--r-sm)] bg-[var(--surface)] border text-[16px] min-[640px]:text-[13px] text-[var(--fg)] outline-none transition-[border-color,box-shadow] duration-[var(--d1)] placeholder:text-[var(--fg-muted)] ${
    hasError
      ? 'border-[var(--expense)]'
      : 'border-[var(--line-strong)] focus:border-[var(--brand)] focus:shadow-[0_0_0_3px_var(--brand-soft)]'
  }`;

const groupOrder = (a: SubscriptionGroup, b: SubscriptionGroup) => a.sort_order - b.sort_order || a.id - b.id;

/* ============================== Dialog shell ============================== */

interface DialogShellProps {
  title: string;
  onClose: () => void;
  small?: boolean;
  initialFocusRef?: RefObject<HTMLElement | null>;
  children: ReactNode;
}

const DialogShell: FC<DialogShellProps> = ({ title, onClose, small = false, initialFocusRef, children }) => {
  const titleId = useId();
  const closeRef = useRef(onClose);
  closeRef.current = onClose;
  const triggerRef = useRef<HTMLElement | null>(null);

  // Mount-only: a re-render must not re-capture the scroll state or steal focus.
  useEffect(() => {
    triggerRef.current = document.activeElement as HTMLElement | null;
    initialFocusRef?.current?.focus();
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.stopPropagation();
        closeRef.current();
      }
    };
    window.addEventListener('keydown', handleKey);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', handleKey);
      if (triggerRef.current?.isConnected) {
        triggerRef.current.focus();
      }
    };
  }, []);

  return createPortal(
    <div
      className="fixed inset-0 z-[1100] bg-[var(--overlay)] backdrop-blur-[4px] flex items-center justify-center p-3 animate-fade"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        onClick={(e) => e.stopPropagation()}
        className={`w-full ${small ? 'max-w-[390px]' : 'max-w-[460px]'} max-h-[calc(100dvh-24px)] overflow-auto
          bg-[var(--surface)] border border-[var(--line)] rounded-[var(--r-xl)]
          shadow-[var(--e4),inset_0_1px_0_var(--highlight-top)] animate-pop`}
      >
        <div className="flex items-center justify-between gap-3 px-[18px] py-3.5 border-b border-[var(--line)]">
          <b id={titleId} className="text-[15px] font-[650] text-[var(--fg)]">
            {title}
          </b>
          <IconButton label="关闭" size={28} onClick={onClose}>
            <CloseIcon size={15} />
          </IconButton>
        </div>
        {children}
      </div>
    </div>,
    document.body
  );
};

/* ============================== Subscription dialog ============================== */

interface SubscriptionDialogProps {
  mode: 'create' | 'edit';
  subscription?: Subscription;
  groups: SubscriptionGroup[];
  defaultGroupId: number | null;
  onClose: () => void;
  onSubmit: (input: SubscriptionInput) => Promise<void>;
  onToast: ToastFn;
}

const SubscriptionDialog: FC<SubscriptionDialogProps> = ({
  mode,
  subscription,
  groups,
  defaultGroupId,
  onClose,
  onSubmit,
  onToast,
}) => {
  const [name, setName] = useState(subscription?.name ?? '');
  const [groupId, setGroupId] = useState(
    subscription?.group_id != null
      ? String(subscription.group_id)
      : defaultGroupId != null
        ? String(defaultGroupId)
        : ''
  );
  const [amountStr, setAmountStr] = useState(subscription ? String(subscription.amount_cents / 100) : '');
  const [dayStr, setDayStr] = useState(subscription ? String(subscription.billing_day) : '');
  const [errors, setErrors] = useState<{ name?: string; amount?: string; day?: string }>({});
  const [submitting, setSubmitting] = useState(false);

  const nameRef = useRef<HTMLInputElement>(null);
  const amountRef = useRef<HTMLInputElement>(null);
  const dayRef = useRef<HTMLInputElement>(null);

  const validate = (): SubscriptionInput | null => {
    const next: typeof errors = {};
    const trimmed = name.trim();
    if (!trimmed) next.name = '请输入服务名称';
    const amount = Number(amountStr);
    if (!Number.isFinite(amount) || amount < 0.01 || amount > 1000000) {
      next.amount = '金额需在 ¥0.01–¥1,000,000.00 之间';
    }
    const day = Number(dayStr);
    if (!Number.isInteger(day) || day < 1 || day > 31) {
      next.day = '扣款日需为 1–31 的整数';
    }
    setErrors(next);
    if (next.name) {
      nameRef.current?.focus();
      return null;
    }
    if (next.amount) {
      amountRef.current?.focus();
      return null;
    }
    if (next.day) {
      dayRef.current?.focus();
      return null;
    }
    return {
      name: trimmed,
      group_id: groupId === '' ? null : Number(groupId),
      amount,
      billing_day: day,
      status: subscription?.status ?? 'active',
    };
  };

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    const input = validate();
    if (!input) return;
    setSubmitting(true);
    try {
      await onSubmit(input);
      onClose();
    } catch (err: unknown) {
      onToast('error', err instanceof Error ? err.message : '操作失败');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <DialogShell
      title={mode === 'edit' ? '编辑订阅' : '添加订阅'}
      onClose={onClose}
      initialFocusRef={nameRef}
    >
      <form onSubmit={handleSubmit} noValidate className="flex flex-col">
        <div className="p-[18px] flex flex-col gap-3.5">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="subscription-name" className="text-xs font-semibold text-[var(--fg-2)]">
              服务名称
            </label>
            <input
              id="subscription-name"
              ref={nameRef}
              type="text"
              maxLength={60}
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                if (errors.name) setErrors((prev) => ({ ...prev, name: undefined }));
              }}
              placeholder="Netflix"
              className={inputClass(Boolean(errors.name))}
            />
            {errors.name && <span className="text-xs text-[var(--expense-text)]">{errors.name}</span>}
          </div>

          <div className="flex flex-col gap-1.5">
            <label htmlFor="subscription-group" className="text-xs font-semibold text-[var(--fg-2)]">
              分组
            </label>
            <select
              id="subscription-group"
              value={groupId}
              onChange={(e) => setGroupId(e.target.value)}
              className={inputClass(false)}
            >
              <option value="">未分组</option>
              {groups.map((group) => (
                <option key={group.id} value={group.id}>
                  {group.name}
                </option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div className="flex flex-col gap-1.5 min-w-0">
              <label htmlFor="subscription-amount" className="text-xs font-semibold text-[var(--fg-2)]">
                每月金额
              </label>
              <div className="relative">
                <span className="absolute left-2.5 top-1/2 -translate-y-1/2 text-[13px] text-[var(--fg-3)] pointer-events-none">
                  ¥
                </span>
                <input
                  id="subscription-amount"
                  ref={amountRef}
                  type="number"
                  inputMode="decimal"
                  min="0.01"
                  max="1000000"
                  step="0.01"
                  value={amountStr}
                  onChange={(e) => {
                    setAmountStr(e.target.value);
                    if (errors.amount) setErrors((prev) => ({ ...prev, amount: undefined }));
                  }}
                  placeholder="0.00"
                  className={`${inputClass(Boolean(errors.amount))} pl-7`}
                />
              </div>
              {errors.amount && <span className="text-xs text-[var(--expense-text)]">{errors.amount}</span>}
            </div>
            <div className="flex flex-col gap-1.5 min-w-0">
              <label htmlFor="subscription-day" className="text-xs font-semibold text-[var(--fg-2)]">
                扣款日
              </label>
              <div className="relative">
                <input
                  id="subscription-day"
                  ref={dayRef}
                  type="number"
                  inputMode="numeric"
                  min="1"
                  max="31"
                  step="1"
                  value={dayStr}
                  onChange={(e) => {
                    setDayStr(e.target.value);
                    if (errors.day) setErrors((prev) => ({ ...prev, day: undefined }));
                  }}
                  placeholder="15"
                  className={`${inputClass(Boolean(errors.day))} pr-7`}
                />
                <span className="absolute right-2.5 top-1/2 -translate-y-1/2 text-[13px] text-[var(--fg-3)] pointer-events-none">
                  日
                </span>
              </div>
              {errors.day && <span className="text-xs text-[var(--expense-text)]">{errors.day}</span>}
            </div>
          </div>
        </div>

        <div className="px-[18px] py-3 border-t border-[var(--line)] flex justify-end gap-2">
          <Button variant="ghost" size="md" onClick={onClose} disabled={submitting}>
            取消
          </Button>
          <Button type="submit" variant="primary" size="md" disabled={submitting}>
            {submitting ? '保存中…' : mode === 'edit' ? '保存' : '添加订阅'}
          </Button>
        </div>
      </form>
    </DialogShell>
  );
};

/* ============================== Group dialog ============================== */

interface GroupDialogProps {
  mode: 'create' | 'rename';
  group?: SubscriptionGroup;
  groups: SubscriptionGroup[];
  onClose: () => void;
  onSubmit: (name: string) => Promise<void>;
  onToast: ToastFn;
}

const GroupDialog: FC<GroupDialogProps> = ({ mode, group, groups, onClose, onSubmit, onToast }) => {
  const [name, setName] = useState(group?.name ?? '');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const nameRef = useRef<HTMLInputElement>(null);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) {
      setError('请输入分组名称');
      nameRef.current?.focus();
      return;
    }
    const duplicate = groups.some(
      (item) => item.id !== group?.id && item.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (duplicate) {
      setError('分组名称已存在');
      nameRef.current?.focus();
      return;
    }
    setSubmitting(true);
    try {
      await onSubmit(trimmed);
      onClose();
    } catch (err: unknown) {
      onToast('error', err instanceof Error ? err.message : '操作失败');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <DialogShell
      title={mode === 'rename' ? '重命名分组' : '新建分组'}
      onClose={onClose}
      small
      initialFocusRef={nameRef}
    >
      <form onSubmit={handleSubmit} noValidate className="flex flex-col">
        <div className="p-[18px] flex flex-col gap-1.5">
          <label htmlFor="group-name" className="text-xs font-semibold text-[var(--fg-2)]">
            分组名称
          </label>
          <input
            id="group-name"
            ref={nameRef}
            type="text"
            maxLength={30}
            value={name}
            onChange={(e) => {
              setName(e.target.value);
              if (error) setError(null);
            }}
            placeholder="影音娱乐"
            className={inputClass(Boolean(error))}
          />
          {error && <span className="text-xs text-[var(--expense-text)]">{error}</span>}
        </div>
        <div className="px-[18px] py-3 border-t border-[var(--line)] flex justify-end gap-2">
          <Button variant="ghost" size="md" onClick={onClose} disabled={submitting}>
            取消
          </Button>
          <Button type="submit" variant="primary" size="md" disabled={submitting}>
            {submitting ? '保存中…' : mode === 'rename' ? '保存' : '创建分组'}
          </Button>
        </div>
      </form>
    </DialogShell>
  );
};

/* ============================== Page ============================== */

export const SubscriptionsPage: FC<SubscriptionsPageProps> = ({ authenticated, onToast }) => {
  const [groups, setGroups] = useState<SubscriptionGroup[]>([]);
  const [subscriptions, setSubscriptions] = useState<Subscription[]>([]);
  const [loading, setLoading] = useState(authenticated);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [refreshError, setRefreshError] = useState<string | null>(null);
  const [filter, setFilter] = useState<SubscriptionFilter>('all');
  const [openMenu, setOpenMenu] = useState<string | null>(null);
  const [subscriptionDialog, setSubscriptionDialog] = useState<SubscriptionDialogState | null>(null);
  const [groupDialog, setGroupDialog] = useState<GroupDialogState | null>(null);
  const [pendingDelete, setPendingDelete] = useState<PendingDelete | null>(null);
  const [deleting, setDeleting] = useState(false);

  // Callbacks from App change identity every render; keep the loader stable.
  const toastRef = useRef(onToast);
  toastRef.current = onToast;

  const load = useCallback(async (mode: 'initial' | 'refresh') => {
    if (mode === 'initial') {
      setLoading(true);
      setLoadError(null);
    }
    try {
      const [nextGroups, nextSubscriptions] = await Promise.all([
        api.getSubscriptionGroups(),
        api.getSubscriptions(),
      ]);
      setGroups(nextGroups);
      setSubscriptions(nextSubscriptions);
      setLoadError(null);
      setRefreshError(null);
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : '加载订阅失败';
      if (mode === 'initial') {
        setGroups([]);
        setSubscriptions([]);
        setLoadError(message);
      } else {
        setRefreshError(message);
        toastRef.current('error', message);
      }
    } finally {
      if (mode === 'initial') setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (authenticated) {
      load('initial');
    }
  }, [authenticated, load]);

  // Esc closes the transient menu layer; dialogs and confirms own their Esc handling.
  useEffect(() => {
    if (!openMenu) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !subscriptionDialog && !groupDialog && !pendingDelete) {
        setOpenMenu(null);
      }
    };
    window.addEventListener('keydown', handleKey);
    return () => window.removeEventListener('keydown', handleKey);
  }, [openMenu, subscriptionDialog, groupDialog, pendingDelete]);

  const now = new Date();
  const orderedGroups = [...groups].sort(groupOrder);
  const allSections = buildSubscriptionSections(groups, subscriptions, 'all', now);
  const visibleSections = buildSubscriptionSections(groups, subscriptions, filter, now);
  const summary = summarizeSubscriptions(subscriptions, now);
  const pausedCount = subscriptions.filter((sub) => sub.status === 'paused').length;
  const isEmpty = groups.length === 0 && subscriptions.length === 0;

  const colorForSection = (section: SubscriptionSection) =>
    section.group
      ? donutColor(orderedGroups.findIndex((group) => group.id === section.group?.id))
      : donutColor(orderedGroups.length);

  const handleSubmitSubscription = async (input: SubscriptionInput) => {
    if (!subscriptionDialog) return;
    if (subscriptionDialog.mode === 'edit' && subscriptionDialog.subscription) {
      await api.updateSubscription(subscriptionDialog.subscription.id, input);
      onToast('success', `订阅「${input.name}」已更新`);
    } else {
      await api.createSubscription(input);
      onToast('success', `订阅「${input.name}」已添加`);
    }
    await load('refresh');
  };

  const handleSubmitGroup = async (name: string) => {
    if (groupDialog?.mode === 'rename' && groupDialog.group) {
      await api.updateSubscriptionGroup(groupDialog.group.id, name, groupDialog.group.sort_order);
      onToast('success', `分组「${name}」已重命名`);
    } else {
      const nextSortOrder = groups.reduce((max, group) => Math.max(max, group.sort_order), 0) + 1;
      await api.createSubscriptionGroup(name, nextSortOrder);
      onToast('success', `分组「${name}」已创建`);
    }
    await load('refresh');
  };

  const handleToggleStatus = async (subscription: Subscription) => {
    const nextStatus = subscription.status === 'active' ? 'paused' : 'active';
    try {
      await api.updateSubscription(subscription.id, {
        name: subscription.name,
        group_id: subscription.group_id,
        amount: subscription.amount_cents / 100,
        billing_day: subscription.billing_day,
        status: nextStatus,
      });
      onToast('success', nextStatus === 'paused' ? '已暂停续费' : '已恢复续费');
    } catch (err: unknown) {
      onToast('error', err instanceof Error ? err.message : '操作失败');
    }
    await load('refresh');
  };

  const handleMoveGroup = async (group: SubscriptionGroup, direction: -1 | 1) => {
    const ordered = [...groups].sort(groupOrder);
    const index = ordered.findIndex((item) => item.id === group.id);
    const target = index + direction;
    if (index < 0 || target < 0 || target >= ordered.length) return;
    [ordered[index], ordered[target]] = [ordered[target], ordered[index]];
    try {
      for (let position = 0; position < ordered.length; position += 1) {
        if (ordered[position].sort_order !== position + 1) {
          await api.updateSubscriptionGroup(ordered[position].id, ordered[position].name, position + 1);
        }
      }
      onToast('success', '分组顺序已更新');
    } catch (err: unknown) {
      onToast('error', err instanceof Error ? err.message : '调整分组顺序失败');
    }
    await load('refresh');
  };

  const handleConfirmDelete = async () => {
    if (!pendingDelete) return;
    setDeleting(true);
    try {
      if (pendingDelete.kind === 'subscription') {
        await api.deleteSubscription(pendingDelete.subscription.id);
        onToast('success', '订阅已删除');
      } else {
        await api.deleteSubscriptionGroup(pendingDelete.group.id);
        onToast('success', '分组已删除，订阅已移至未分组');
      }
      setPendingDelete(null);
      await load('refresh');
    } catch (err: unknown) {
      onToast('error', err instanceof Error ? err.message : '删除失败');
    } finally {
      setDeleting(false);
    }
  };

  const groupMenuItems = (section: SubscriptionSection, groupIndex: number): OverflowMenuItem[] => {
    const group = section.group;
    if (!group) return [];
    return [
      { label: '在此分组添加订阅', onSelect: () => setSubscriptionDialog({ mode: 'create', defaultGroupId: group.id }) },
      { label: '重命名分组', onSelect: () => setGroupDialog({ mode: 'rename', group }) },
      { label: '上移', disabled: groupIndex === 0, onSelect: () => handleMoveGroup(group, -1) },
      { label: '下移', disabled: groupIndex === orderedGroups.length - 1, onSelect: () => handleMoveGroup(group, 1) },
      'divider',
      { label: '删除分组', tone: 'danger', onSelect: () => setPendingDelete({ kind: 'group', group }) },
    ];
  };

  const renderRow = (subscription: Subscription) => {
    const paused = subscription.status === 'paused';
    const initial = subscription.name.trim().charAt(0).toUpperCase();

    return (
      <div
        key={subscription.id}
        className={`flex items-center gap-2.5 min-h-[62px] py-2 pr-1.5 pl-3.5 border-t border-[var(--line)] first:border-t-0 transition-colors ${
          paused ? 'bg-[var(--surface-sunken)]' : 'hover:bg-[var(--surface-hover)]'
        }`}
      >
        <div
          aria-hidden
          className={`w-[34px] h-[34px] rounded-[var(--r-sm)] flex items-center justify-center flex-shrink-0 text-sm font-bold tracking-[-.02em] ${
            paused
              ? 'bg-[var(--surface-sunken)] border border-[var(--line)] text-[var(--fg-3)]'
              : 'bg-[var(--brand-soft)] border border-[var(--brand-line)] text-[var(--brand-text)]'
          }`}
        >
          {initial}
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-[7px] min-w-0">
            <b className="text-[13.5px] font-[650] truncate">{subscription.name}</b>
            {paused && (
              <span className="flex-shrink-0 px-1.5 py-px rounded-[var(--r-pill)] bg-[var(--surface-sunken)] border border-[var(--line)] text-[10.5px] font-semibold text-[var(--fg-3)]">
                已暂停
              </span>
            )}
          </div>
          <div className="mt-px text-[11.5px] text-[var(--fg-3)] overflow-hidden text-ellipsis whitespace-nowrap max-[380px]:whitespace-normal max-[380px]:leading-[1.35]">
            <span className="max-[380px]:block">
              {paused ? `原扣款日 ${subscription.billing_day} 日` : `每月 ${subscription.billing_day} 日`}
            </span>
            {!paused && (
              <span className="max-[380px]:block">
                <span className="mx-1 max-[380px]:hidden">·</span>
                {`下次 ${formatRenewalDate(nextRenewalDate(subscription.billing_day, now))}`}
              </span>
            )}
          </div>
        </div>

        <div className="flex-shrink-0 text-right whitespace-nowrap">
          <b className={`num text-sm ${paused ? 'text-[var(--fg-3)] font-[550]' : 'font-[650]'}`}>
            {formatMoney(subscription.amount_cents / 100, { sign: 'none' })}
          </b>
          <small className="ml-1 text-[11px] font-medium text-[var(--fg-3)]">/ 月</small>
        </div>

        <OverflowMenu
          label={subscription.name}
          open={openMenu === `sub-${subscription.id}`}
          onOpenChange={(isOpen) => setOpenMenu(isOpen ? `sub-${subscription.id}` : null)}
          items={[
            { label: '编辑', onSelect: () => setSubscriptionDialog({ mode: 'edit', subscription }) },
            {
              label: paused ? '恢复续费' : '暂停续费',
              onSelect: () => handleToggleStatus(subscription),
            },
            'divider',
            {
              label: '删除',
              tone: 'danger',
              onSelect: () => setPendingDelete({ kind: 'subscription', subscription }),
            },
          ]}
        />
      </div>
    );
  };

  const renderSection = (section: SubscriptionSection) => {
    const group = section.group;
    const isPausedView = filter === 'paused';
    const countLabel = isPausedView
      ? `${section.totalCount - section.activeCount} 项已暂停`
      : `${section.activeCount} 项使用中`;
    // A paused-only filter keeps the group's active subtotal; dash means it has no active amount.
    const showDash = isPausedView && section.activeCount === 0;
    const groupIndex = group ? orderedGroups.findIndex((item) => item.id === group.id) : -1;

    return (
      <Panel key={section.key} className="p-0 overflow-visible">
        <div className="flex items-center gap-2.5 min-h-[48px] py-[7px] pr-2.5 pl-3.5 bg-[var(--surface-sunken)] border-b border-[var(--line)] rounded-t-[var(--r-lg)]">
          <div className="flex items-center gap-2 min-w-0">
            {group && (
              <i
                aria-hidden
                className="w-2 h-2 rounded-[2px] flex-shrink-0"
                style={{ background: colorForSection(section) }}
              />
            )}
            <b className="text-[13px] font-[650] truncate">{section.name}</b>
            <span className="text-[11.5px] text-[var(--fg-3)] font-medium whitespace-nowrap">{countLabel}</span>
          </div>
          <div className="ml-auto flex items-center gap-1">
            <span
              className={`text-[12.5px] whitespace-nowrap ${
                showDash ? 'text-[var(--fg-muted)] font-medium' : 'font-[650]'
              }`}
            >
              {showDash
                ? '—'
                : `${formatMoney(section.monthlyCents / 100, { sign: 'none' })} / 月`}
            </span>
            {group && (
              <OverflowMenu
                label={`${section.name} 分组`}
                open={openMenu === `group-${group.id}`}
                onOpenChange={(isOpen) => setOpenMenu(isOpen ? `group-${group.id}` : null)}
                items={groupMenuItems(section, groupIndex)}
              />
            )}
          </div>
        </div>

        {section.items.length > 0 ? (
          section.items.map(renderRow)
        ) : (
          <div className="flex items-center justify-between gap-3 px-3.5 py-3 text-xs text-[var(--fg-3)]">
            <span>暂无订阅</span>
            <button
              type="button"
              onClick={() => setSubscriptionDialog({ mode: 'create', defaultGroupId: group?.id ?? null })}
              className="font-semibold text-[var(--brand-text)] cursor-pointer hover:underline"
            >
              添加
            </button>
          </div>
        )}
      </Panel>
    );
  };

  let deleteDescription = '删除后不可恢复。';
  let deleteDetail: string | undefined;
  if (pendingDelete?.kind === 'group') {
    const groupItemCount = subscriptions.filter((sub) => sub.group_id === pendingDelete.group.id).length;
    deleteDescription = `组内 ${groupItemCount} 项订阅将移至未分组。`;
    deleteDetail = pendingDelete.group.name;
  } else if (pendingDelete?.kind === 'subscription') {
    deleteDetail = pendingDelete.subscription.name;
  }

  return (
    <div className="flex flex-col pb-4">
      <div className="flex items-center justify-between gap-3 flex-wrap mb-[18px]">
        <h1 className="m-0 text-xl leading-[1.3] font-[680] tracking-[-.018em]">订阅</h1>
        <div className="flex items-center gap-2 ml-auto">
          <Button variant="ghost" size="sm" onClick={() => setGroupDialog({ mode: 'create' })}>
            <PlusIcon size={14} />
            新建分组
          </Button>
          <Button
            variant="primary"
            size="sm"
            onClick={() => setSubscriptionDialog({ mode: 'create', defaultGroupId: null })}
          >
            <PlusIcon size={14} />
            添加订阅
          </Button>
        </div>
      </div>

      {loading ? (
        <div className="flex flex-col gap-4" aria-hidden="true">
          <Skeleton className="h-[190px] rounded-[var(--r-xl)]" />
          <Skeleton className="h-[168px] rounded-[var(--r-lg)]" />
          <Skeleton className="h-[168px] rounded-[var(--r-lg)]" />
        </div>
      ) : loadError ? (
        <Panel>
          <EmptyState
            icon={<AlertIcon size={18} />}
            title="订阅加载失败"
            subtitle={loadError}
            action={{ label: '重试', onClick: () => load('initial') }}
          />
        </Panel>
      ) : isEmpty ? (
        <Panel>
          <EmptyState
            icon={<PlusIcon size={18} />}
            title="还没有订阅"
            action={{
              label: '添加第一个订阅',
              onClick: () => setSubscriptionDialog({ mode: 'create', defaultGroupId: null }),
            }}
          />
        </Panel>
      ) : (
        <>
          <Panel variant="hero" className="p-[22px] min-[720px]:px-[26px] pb-5">
            <div className="grid grid-cols-1 min-[640px]:grid-cols-[minmax(0,1fr)_auto] gap-[18px] min-[640px]:gap-6 items-end">
              <div>
                <div className="flex items-center gap-2 flex-wrap text-[12.5px] font-semibold tracking-[.01em] text-[var(--fg-3)]">
                  <span>每月固定开支</span>
                  <Chip tone="brand">{summary.activeCount} 项使用中</Chip>
                </div>
                <div className="mt-1 flex items-baseline">
                  <span className="num text-2xl font-medium text-[var(--fg-2)] mr-1">¥</span>
                  <span className="num text-[34px] min-[720px]:text-[40px] font-[680] tracking-[-.028em] leading-[1.05]">
                    {formatMoney(summary.monthlyCents / 100, { sign: 'none', withCurrency: false })}
                  </span>
                  <span className="ml-1 text-[13px] font-medium text-[var(--fg-3)]">/ 月</span>
                </div>
              </div>
              <div className="grid grid-cols-2 gap-x-6 gap-y-2 min-w-[230px]">
                <div className="flex flex-col gap-px">
                  <span className="text-[11.5px] text-[var(--fg-3)]">年度预估</span>
                  <b className="num text-sm font-[650] whitespace-nowrap">
                    {formatMoney(summary.annualCents / 100, { sign: 'none' })}
                  </b>
                </div>
                <div className="flex flex-col gap-px">
                  <span className="text-[11.5px] text-[var(--fg-3)]">未来 7 天</span>
                  <b className="num text-sm font-[650] whitespace-nowrap">
                    {formatMoney(summary.upcomingCents / 100, { sign: 'none' })}
                    <small className="ml-1 text-[11px] font-medium text-[var(--fg-3)]">
                      {summary.upcomingCount} 项
                    </small>
                  </b>
                </div>
              </div>
            </div>
            <div
              role="img"
              aria-label="按分组划分的每月固定开支"
              className="flex gap-[2px] h-[7px] mt-[18px] overflow-hidden bg-[var(--surface-sunken)] rounded-[var(--r-pill)]"
            >
              {allSections
                .filter((section) => section.monthlyCents > 0)
                .map((section) => (
                  <i
                    key={section.key}
                    className="block h-full"
                    style={{ flexGrow: section.monthlyCents, flexBasis: 0, background: colorForSection(section) }}
                  />
                ))}
            </div>
          </Panel>

          <div className="flex items-center justify-between gap-2.5 flex-wrap mt-[18px] mb-3">
            <div
              role="group"
              aria-label="订阅状态筛选"
              className="inline-flex gap-[2px] p-[3px] bg-[var(--surface-sunken)] border border-[var(--line)] rounded-[var(--r-pill)]"
            >
              {FILTERS.map((item) => {
                const selected = filter === item.key;
                return (
                  <button
                    key={item.key}
                    type="button"
                    aria-pressed={selected}
                    onClick={() => setFilter(item.key)}
                    className={`min-h-[30px] px-3 rounded-[var(--r-pill)] text-[12.5px] cursor-pointer transition-all duration-[var(--d1)] ${
                      selected
                        ? 'bg-[var(--surface)] text-[var(--fg)] font-[650] shadow-[var(--e1)]'
                        : 'text-[var(--fg-3)] font-medium hover:text-[var(--fg)]'
                    }`}
                  >
                    {item.label}
                  </button>
                );
              })}
            </div>
            <span className="text-xs text-[var(--fg-3)]">
              {filter === 'paused' ? `${pausedCount} 项已暂停` : `共 ${subscriptions.length} 项`}
            </span>
          </div>

          {refreshError && (
            <div
              role="status"
              className="mb-3 flex items-center justify-between gap-3 rounded-[var(--r-sm)] border border-[var(--expense-line)] bg-[var(--expense-soft)] px-3 py-2 text-xs text-[var(--expense-text)]"
            >
              <span className="min-w-0 truncate">数据未同步：{refreshError}</span>
              <button
                type="button"
                onClick={() => load('refresh')}
                className="font-semibold flex-shrink-0 cursor-pointer hover:underline"
              >
                重试
              </button>
            </div>
          )}

          <div className="flex flex-col gap-3.5">
            {visibleSections.length > 0 ? (
              visibleSections.map(renderSection)
            ) : (
              <Panel>
                <EmptyState
                  icon={<PlusIcon size={18} />}
                  title={filter === 'paused' ? '暂无已暂停的订阅' : '暂无使用中的订阅'}
                  action={{ label: '查看全部', onClick: () => setFilter('all') }}
                />
              </Panel>
            )}
          </div>
        </>
      )}

      {subscriptionDialog && (
        <SubscriptionDialog
          mode={subscriptionDialog.mode}
          subscription={subscriptionDialog.subscription}
          groups={orderedGroups}
          defaultGroupId={subscriptionDialog.defaultGroupId ?? null}
          onClose={() => setSubscriptionDialog(null)}
          onSubmit={handleSubmitSubscription}
          onToast={onToast}
        />
      )}

      {groupDialog && (
        <GroupDialog
          mode={groupDialog.mode}
          group={groupDialog.group}
          groups={groups}
          onClose={() => setGroupDialog(null)}
          onSubmit={handleSubmitGroup}
          onToast={onToast}
        />
      )}

      <ConfirmDialog
        open={pendingDelete !== null}
        title={pendingDelete?.kind === 'group' ? '删除分组' : '删除订阅'}
        description={deleteDescription}
        detail={deleteDetail}
        confirmLabel="删除"
        tone="danger"
        loading={deleting}
        onConfirm={handleConfirmDelete}
        onCancel={() => setPendingDelete(null)}
      />
    </div>
  );
};
