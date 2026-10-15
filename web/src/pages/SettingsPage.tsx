import { useState, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import type { FC, FormEvent } from 'react';
import { Category, PaymentMethod, Tag } from '../lib/api';
import { formatMoney } from '../lib/format.ts';
import {
  Panel,
  SegmentedControl,
  IconButton,
  Button,
  Chip,
  EmptyState,
  ConfirmDialog,
  Skeleton,
  OverflowMenu,
} from '../components/primitives';
import {
  PlusIcon,
  CloseIcon,
  ChevronRightIcon,
  LockIcon,
} from '../components/Icons';

interface SettingsPageProps {
  initialSection?: 'categories' | 'paymentMethods';
  categories: Category[];
  paymentMethods: PaymentMethod[];
  loading?: boolean;
  onAddPaymentMethod: (name: string, type: 'asset' | 'liability', initialBalance: number, creditLimit: number) => Promise<void>;
  onUpdatePaymentMethod: (id: number, name: string, sort_order: number, type: 'asset' | 'liability', initialBalance: number, creditLimit: number) => Promise<void>;
  onDeletePaymentMethod: (id: number) => Promise<void>;
  onAddCategory: (name: string, type?: 'expense' | 'income') => Promise<void>;
  onUpdateCategory: (id: number, name: string, sort_order: number, type?: 'expense' | 'income') => Promise<void>;
  onReorderCategories: (updates: { id: number; name: string; sort_order: number }[]) => Promise<void>;
  onDeleteCategory: (id: number) => Promise<void>;
  onAddTag: (categoryId: number, name: string) => Promise<void>;
  onUpdateTag: (id: number, name: string, sort_order: number) => Promise<void>;
  onDeleteTag: (id: number) => Promise<void>;
  onToast?: (type: 'success' | 'error' | 'info', message: string) => void;
}

type PendingDelete = { kind: 'category' | 'channel' | 'tag'; id: number; name: string } | null;

type ChannelDialogState =
  | { mode: 'create'; type: 'asset' | 'liability' }
  | { mode: 'edit'; pm: PaymentMethod }
  | null;

const INPUT_CLASS =
  'px-3 py-1.5 rounded-[var(--r-sm)] bg-[var(--surface)] border border-[var(--line-strong)] ' +
  'text-[16px] min-[640px]:text-xs text-[var(--fg)] outline-none placeholder:text-[var(--fg-muted)] ' +
  'focus:border-[var(--brand)] focus:shadow-[0_0_0_3px_var(--brand-soft)] ' +
  'transition-[border-color,box-shadow] duration-[var(--d1)]';

const SkeletonList: FC = () => (
  <div className="p-1.5 flex flex-col">
    {[1, 2, 3, 4].map((i) => (
      <div key={i} className="min-h-[52px] px-3 py-2 flex items-center">
        <div className="flex-1 flex flex-col gap-1.5">
          <Skeleton className="w-[30%] h-3.5" />
          <Skeleton className="w-[55%] h-2.5" />
        </div>
      </div>
    ))}
  </div>
);

export const SettingsPage: FC<SettingsPageProps> = ({
  initialSection,
  categories,
  paymentMethods,
  loading = false,
  onAddPaymentMethod,
  onUpdatePaymentMethod,
  onDeletePaymentMethod,
  onAddCategory,
  onUpdateCategory,
  onReorderCategories,
  onDeleteCategory,
  onAddTag,
  onUpdateTag,
  onDeleteTag,
  onToast,
}) => {
  // Navigation tab state: 2 core business sections
  const [activeTab, setActiveTab] = useState<'categories' | 'paymentMethods'>(
    initialSection ?? 'categories'
  );

  // Single controlled overflow menu state
  const [openMenu, setOpenMenu] = useState<string | null>(null);

  // Channel dialog state
  const [channelDialog, setChannelDialog] = useState<ChannelDialogState>(null);

  // Category inline add & type tab state
  const [categoryTypeTab, setCategoryTypeTab] = useState<'expense' | 'income'>('expense');
  const [newCatName, setNewCatName] = useState('');
  const [showAddCatInput, setShowAddCatInput] = useState(false);

  // Drawer & Tag state (Layer 3 Drawer container bound to SSOT activeCategoryId)
  const [activeDrawerCategoryId, setActiveDrawerCategoryId] = useState<number | null>(null);
  const [drawerNewTagName, setDrawerNewTagName] = useState('');
  const isCreatingTagRef = useRef(false);
  const [isSubmittingTag, setIsSubmittingTag] = useState(false);
  const drawerTriggerRef = useRef<HTMLElement | null>(null);
  const prevDrawerCatIdRef = useRef<number | null>(null);
  const drawerNewTagInputRef = useRef<HTMLInputElement>(null);
  const drawerCloseBtnRef = useRef<HTMLButtonElement>(null);

  // Derive active category directly from SSOT
  const activeDrawerCategory = categories.find((c) => c.id === activeDrawerCategoryId);

  // Inline rename states
  const [editingCatId, setEditingCatId] = useState<number | null>(null);
  const [editingCatName, setEditingCatName] = useState('');
  const [editingCatType, setEditingCatType] = useState<'expense' | 'income'>('expense');

  const [editingTagId, setEditingTagId] = useState<number | null>(null);
  const [editingTagName, setEditingTagName] = useState('');

  // Single confirmation host shared by category / channel / tag deletion
  const [pendingDelete, setPendingDelete] = useState<PendingDelete>(null);

  const openDrawer = (catId: number, triggerEl?: HTMLElement | null) => {
    setOpenMenu(null);
    drawerTriggerRef.current = triggerEl ?? (document.activeElement as HTMLElement | null);
    setActiveDrawerCategoryId(catId);
    setDrawerNewTagName('');
    setEditingTagId(null);
    setEditingTagName('');
  };

  const closeDrawer = () => {
    setActiveDrawerCategoryId(null);
    setDrawerNewTagName('');
    setEditingTagId(null);
    setEditingTagName('');
    isCreatingTagRef.current = false;
    setIsSubmittingTag(false);
    if (drawerTriggerRef.current?.isConnected) {
      drawerTriggerRef.current.focus();
    }
    drawerTriggerRef.current = null;
  };

  // Close drawer if active category was removed from parent categories
  useEffect(() => {
    if (activeDrawerCategoryId !== null && !activeDrawerCategory) {
      closeDrawer();
    }
  }, [activeDrawerCategoryId, activeDrawerCategory]);

  // Lock background scroll while the drawer is open
  useEffect(() => {
    if (!activeDrawerCategory) return;
    const prev = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = prev;
    };
  }, [activeDrawerCategory]);

  // Initial focus on drawer open transition (null -> catId), avoids re-stealing on category refresh
  useEffect(() => {
    if (activeDrawerCategoryId !== null && prevDrawerCatIdRef.current === null) {
      if (activeDrawerCategory?.type === 'system') {
        drawerCloseBtnRef.current?.focus();
      } else {
        drawerNewTagInputRef.current?.focus();
      }
    }
    prevDrawerCatIdRef.current = activeDrawerCategoryId;
  }, [activeDrawerCategoryId, activeDrawerCategory?.type]);

  // ESC key listener with prioritized arbitration chain
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (pendingDelete !== null) {
          // Yield to ConfirmDialog
          return;
        }
        if (channelDialog !== null) {
          setChannelDialog(null);
          return;
        }
        if (openMenu !== null) {
          setOpenMenu(null);
          return;
        }
        if (activeDrawerCategory) {
          if (editingTagId !== null) {
            setEditingTagId(null);
            setEditingTagName('');
          } else {
            closeDrawer();
          }
          return;
        }
        if (editingCatId !== null) {
          setEditingCatId(null);
        } else if (showAddCatInput) {
          setShowAddCatInput(false);
          setNewCatName('');
        }
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [
    pendingDelete,
    channelDialog,
    openMenu,
    activeDrawerCategory,
    editingTagId,
    editingCatId,
    showAddCatInput,
  ]);

  const expenseCategories = categories.filter((c) => (c.type || 'expense') === 'expense');
  const incomeCategories = categories.filter((c) => c.type === 'income');
  const systemCategories = categories.filter((c) => c.type === 'system');

  const currentCategories = categoryTypeTab === 'expense' ? expenseCategories : incomeCategories;

  const handleCreateCategory = async (e: FormEvent) => {
    e.preventDefault();
    const trimmed = newCatName.trim();
    if (!trimmed) return;
    const isDuplicate = categories.some(
      (c) => (c.type || 'expense') === categoryTypeTab && c.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (isDuplicate) {
      onToast?.('error', '该类型名称已存在');
      return;
    }
    await onAddCategory(trimmed, categoryTypeTab);
    setNewCatName('');
    setShowAddCatInput(false);
  };

  const handleCreateTagInDrawer = async (categoryId: number, e: FormEvent) => {
    e.preventDefault();
    if (isCreatingTagRef.current) return;

    const trimmed = drawerNewTagName.trim();
    if (!trimmed) return;

    // Pre-check duplicate in current category tags
    const currentCategory = categories.find((c) => c.id === categoryId);
    const isDuplicate = currentCategory?.tags?.some(
      (t) => t.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (isDuplicate) {
      onToast?.('error', '该分类下已存在同名细分标签');
      return;
    }

    isCreatingTagRef.current = true;
    setIsSubmittingTag(true);
    try {
      await onAddTag(categoryId, trimmed);
      setDrawerNewTagName('');
    } catch {
      // Keep draft on failure; error toast already shown by App
    } finally {
      isCreatingTagRef.current = false;
      setIsSubmittingTag(false);
    }
  };

  const handleMoveCategory = async (index: number, direction: 'up' | 'down') => {
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= currentCategories.length) return;

    const itemA = currentCategories[index];
    const itemB = currentCategories[targetIndex];

    let orderForA: number;
    let orderForB: number;

    if (itemA.sort_order !== itemB.sort_order) {
      orderForA = itemB.sort_order;
      orderForB = itemA.sort_order;
    } else {
      orderForA = targetIndex + 1;
      orderForB = index + 1;
    }

    try {
      await onReorderCategories([
        { id: itemA.id, name: itemA.name, sort_order: orderForA },
        { id: itemB.id, name: itemB.name, sort_order: orderForB },
      ]);
    } catch {
      // Toast and refresh handled in parent
    }
  };

  const handleSaveCatRename = async (cat: Category, e: FormEvent) => {
    e.preventDefault();
    const trimmed = editingCatName.trim();
    if (!trimmed) {
      onToast?.('error', '分类名称不能为空');
      return;
    }
    const typeChanged = editingCatType !== (cat.type || 'expense');
    if (trimmed === cat.name && !typeChanged) {
      setEditingCatId(null);
      return;
    }

    // Pre-check duplicate in categories with the same target type
    const isDuplicate = categories.some(
      (c) => c.id !== cat.id && (c.type || 'expense') === editingCatType && c.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (isDuplicate) {
      onToast?.('error', '该类型名称已存在');
      return;
    }

    try {
      await onUpdateCategory(cat.id, trimmed, cat.sort_order, editingCatType);
      setEditingCatId(null);
    } catch {
      // Keep edit state open so user can adjust name
    }
  };

  const handleSaveTagRename = async (tag: Tag, e: FormEvent, currentCategory?: Category) => {
    e.preventDefault();
    const trimmed = editingTagName.trim();
    if (!trimmed || trimmed === tag.name) {
      setEditingTagId(null);
      return;
    }

    // Pre-check duplicate in same category tags
    const parentCategory = currentCategory || categories.find((c) => c.id === tag.category_id);
    const isDuplicate = parentCategory?.tags?.some(
      (t) => t.id !== tag.id && t.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (isDuplicate) {
      onToast?.('error', '该分类下已存在同名标签');
      return;
    }

    try {
      await onUpdateTag(tag.id, trimmed, tag.sort_order);
      setEditingTagId(null);
    } catch {
      // Keep edit state open so user can adjust name
    }
  };

  // Single confirm host dispatch — errors (409 conflicts) surface via App toasts
  const handleConfirmDelete = async () => {
    if (!pendingDelete) return;
    const { kind, id } = pendingDelete;
    setPendingDelete(null);
    if (kind === 'category') await onDeleteCategory(id);
    else if (kind === 'channel') await onDeletePaymentMethod(id);
    else await onDeleteTag(id);
  };

  const handleSaveChannel = async (
    name: string,
    type: 'asset' | 'liability',
    initialBal: number,
    creditLimit: number
  ) => {
    if (!channelDialog) return;
    if (channelDialog.mode === 'create') {
      await onAddPaymentMethod(name, type, initialBal, creditLimit);
    } else {
      const pm = channelDialog.pm;
      await onUpdatePaymentMethod(pm.id, name, pm.sort_order, type, initialBal, creditLimit);
    }
  };

  // Derive asset and liability channels
  const assetChannels = paymentMethods.filter((pm) => pm.type === 'asset' || !pm.type);
  const liabilityChannels = paymentMethods.filter((pm) => pm.type === 'liability');

  return (
    <div className="flex flex-col pb-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3 mb-[18px]">
        <h3 className="text-xl font-[680] tracking-[-.018em] text-[var(--fg)]">设置</h3>
        <SegmentedControl
          items={[
            { key: 'categories', label: '分类与标签' },
            { key: 'paymentMethods', label: '渠道与账户' },
          ]}
          value={activeTab}
          onChange={(key) => {
            setActiveTab(key as 'categories' | 'paymentMethods');
            setOpenMenu(null);
          }}
          ariaLabel="设置分区"
          className="[&>button]:px-3.5"
        />
      </div>

      {/* ==================== Section 1: Categories & Tags ==================== */}
      {activeTab === 'categories' && (
        <div className="flex flex-col gap-4">
          <Panel className="p-0">
            {/* Panel Header */}
            <div className="flex items-center justify-between gap-2.5 px-[18px] pt-3.5 pb-2.5">
              <SegmentedControl
                items={[
                  { key: 'expense', label: '支出' },
                  { key: 'income', label: '收入' },
                ]}
                value={categoryTypeTab}
                onChange={(key) => {
                  setCategoryTypeTab(key as 'expense' | 'income');
                  setShowAddCatInput(false);
                  setOpenMenu(null);
                }}
                ariaLabel="分类类型"
                className="[&>button]:px-3 [&>button]:py-1 [&>button]:text-xs"
              />
              <Button
                variant="subtle"
                size="sm"
                onClick={() => {
                  setShowAddCatInput(true);
                  setOpenMenu(null);
                }}
              >
                <PlusIcon size={13} />
                新建分类
              </Button>
            </div>

            {/* Inline Creation Form */}
            {showAddCatInput && (
              <div className="px-3 pb-3">
                <form
                  onSubmit={handleCreateCategory}
                  className="flex items-center gap-2 p-3 bg-[var(--surface-sunken)] rounded-[var(--r-md)] border border-[var(--line)] animate-fade"
                >
                  <input
                    type="text"
                    autoFocus
                    value={newCatName}
                    onChange={(e) => setNewCatName(e.target.value)}
                    placeholder={
                      categoryTypeTab === 'income'
                        ? '输入收入分类名称 (如：职业收入、理财利息)'
                        : '输入支出分类名称 (如：数码科技、宠物养护)'
                    }
                    className={`flex-1 ${INPUT_CLASS}`}
                  />
                  <Button type="submit" variant="primary" size="sm">
                    确定
                  </Button>
                  <Button
                    variant="subtle"
                    size="sm"
                    onClick={() => {
                      setShowAddCatInput(false);
                      setNewCatName('');
                    }}
                  >
                    取消
                  </Button>
                </form>
              </div>
            )}

            {/* List or Skeleton or Empty */}
            {loading ? (
              <SkeletonList />
            ) : currentCategories.length === 0 ? (
              <EmptyState
                title={`暂无${categoryTypeTab === 'income' ? '收入分类' : '支出分类'}`}
                subtitle="新建后即可在记账时选择"
                action={{
                  label: '新建分类',
                  onClick: () => {
                    setShowAddCatInput(true);
                    setOpenMenu(null);
                  },
                }}
              />
            ) : (
              <div className="p-1.5 flex flex-col">
                {currentCategories.map((cat, index) => {
                  if (editingCatId === cat.id) {
                    return (
                      <div key={cat.id} className="p-2 border-t border-[var(--line)] first:border-t-0">
                        <form
                          onSubmit={(e) => handleSaveCatRename(cat, e)}
                          className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2 animate-fade"
                        >
                          <input
                            type="text"
                            autoFocus
                            value={editingCatName}
                            onChange={(e) => setEditingCatName(e.target.value)}
                            className={`flex-1 ${INPUT_CLASS}`}
                          />
                          <div className="flex items-center gap-1 bg-[var(--surface-sunken)] p-0.5 rounded-[var(--r-sm)] border border-[var(--line)] text-xs">
                            {(['expense', 'income'] as const).map((t) => (
                              <button
                                key={t}
                                type="button"
                                aria-pressed={editingCatType === t}
                                onClick={() => setEditingCatType(t)}
                                className={`px-2.5 py-1 rounded-[var(--r-xs)] text-xs font-medium cursor-pointer transition-colors ${
                                  editingCatType === t
                                    ? 'bg-[var(--surface)] text-[var(--fg)] font-semibold shadow-[var(--e1)]'
                                    : 'text-[var(--fg-3)] hover:text-[var(--fg-2)]'
                                }`}
                              >
                                {t === 'expense' ? '支出' : '收入'}
                              </button>
                            ))}
                          </div>
                          <div className="flex items-center gap-1.5 justify-end">
                            <Button type="submit" variant="primary" size="sm">
                              保存
                            </Button>
                            <Button variant="subtle" size="sm" onClick={() => setEditingCatId(null)}>
                              取消
                            </Button>
                          </div>
                        </form>
                      </div>
                    );
                  }

                  const tagSummary =
                    cat.tags && cat.tags.length > 0
                      ? cat.tags.map((t) => t.name).join(' · ')
                      : '暂无细分标签';

                  return (
                    <div
                      key={cat.id}
                      className="flex items-center gap-2.5 min-h-[52px] px-3 py-2 rounded-[10px] hover:bg-[var(--surface-hover)] transition-colors border-t border-[var(--line)] first:border-t-0"
                    >
                      <button
                        type="button"
                        onClick={(e) => openDrawer(cat.id, e.currentTarget)}
                        className="flex-1 min-w-0 text-left flex flex-col justify-center cursor-pointer"
                      >
                        <span className="text-[13.5px] font-semibold text-[var(--fg)] truncate">
                          {cat.name}
                        </span>
                        <span className="text-xs text-[var(--fg-3)] truncate mt-0.5">
                          {tagSummary}
                        </span>
                      </button>

                      <span className="text-xs text-[var(--fg-muted)] num flex-shrink-0">
                        {cat.tags?.length || 0}
                      </span>

                      <OverflowMenu
                        label={cat.name}
                        open={openMenu === `cat-${cat.id}`}
                        onOpenChange={(isOpen) => setOpenMenu(isOpen ? `cat-${cat.id}` : null)}
                        items={[
                          {
                            label: '重命名',
                            onSelect: () => {
                              setEditingCatId(cat.id);
                              setEditingCatName(cat.name);
                              setEditingCatType(cat.type === 'income' ? 'income' : 'expense');
                            },
                          },
                          {
                            label: '上移',
                            disabled: index === 0,
                            onSelect: () => handleMoveCategory(index, 'up'),
                          },
                          {
                            label: '下移',
                            disabled: index === currentCategories.length - 1,
                            onSelect: () => handleMoveCategory(index, 'down'),
                          },
                          'divider',
                          {
                            label: '删除',
                            tone: 'danger',
                            onSelect: () =>
                              setPendingDelete({ kind: 'category', id: cat.id, name: cat.name }),
                          },
                        ]}
                      />
                    </div>
                  );
                })}
              </div>
            )}
          </Panel>

          {/* System Categories Panel */}
          {systemCategories.length > 0 && !loading && (
            <Panel className="p-0">
              <div className="flex items-center justify-between gap-2.5 px-[18px] py-3.5 border-b border-[var(--line)]">
                <h2 className="text-sm font-[650] text-[var(--fg)]">系统分类</h2>
              </div>
              <div className="p-1.5 flex flex-col">
                {systemCategories.map((cat) => {
                  const tagSummary =
                    cat.tags && cat.tags.length > 0
                      ? cat.tags.map((t) => t.name).join(' · ')
                      : '暂无细分标签';

                  return (
                    <div
                      key={cat.id}
                      className="flex items-center gap-2.5 min-h-[52px] px-3 py-2 rounded-[10px] hover:bg-[var(--surface-hover)] transition-colors border-t border-[var(--line)] first:border-t-0"
                    >
                      <button
                        type="button"
                        onClick={(e) => openDrawer(cat.id, e.currentTarget)}
                        className="flex-1 min-w-0 text-left flex flex-col justify-center cursor-pointer"
                      >
                        <span className="text-[13.5px] font-semibold text-[var(--fg)] truncate">
                          {cat.name}
                        </span>
                        <span className="text-xs text-[var(--fg-3)] truncate mt-0.5">
                          {tagSummary}
                        </span>
                      </button>

                      <span className="inline-flex items-center gap-1 text-[11.5px] text-[var(--fg-3)] flex-shrink-0">
                        <LockIcon size={12} />
                        系统
                      </span>
                      <ChevronRightIcon size={14} className="text-[var(--fg-muted)] flex-shrink-0" />
                    </div>
                  );
                })}
              </div>
            </Panel>
          )}
        </div>
      )}

      {/* ==================== Section 2: Channels & Accounts ==================== */}
      {activeTab === 'paymentMethods' && (
        <div className="grid grid-cols-1 min-[720px]:grid-cols-2 gap-4">
          {/* Asset Channels Panel */}
          <Panel className="p-0 flex flex-col">
            <div className="flex items-center justify-between gap-2.5 px-[18px] py-3.5 border-b border-[var(--line)]">
              <h2 className="text-sm font-[650] text-[var(--fg)] flex items-baseline gap-2">
                资产渠道
                <span className="text-[11.5px] font-semibold text-[var(--fg-3)] num">
                  {assetChannels.length}
                </span>
              </h2>
              <Button
                variant="subtle"
                size="sm"
                onClick={() => {
                  setChannelDialog({ mode: 'create', type: 'asset' });
                  setOpenMenu(null);
                }}
              >
                <PlusIcon size={13} />
                添加
              </Button>
            </div>

            {loading ? (
              <SkeletonList />
            ) : assetChannels.length === 0 ? (
              <EmptyState
                title="暂无资产渠道"
                subtitle="用于记录支出与收入"
                action={{
                  label: '添加资产渠道',
                  onClick: () => {
                    setChannelDialog({ mode: 'create', type: 'asset' });
                    setOpenMenu(null);
                  },
                }}
              />
            ) : (
              <div className="p-1.5 flex flex-col">
                {assetChannels.map((pm) => (
                  <div
                    key={pm.id}
                    className="flex items-center gap-2.5 min-h-[52px] px-3 py-2 rounded-[10px] hover:bg-[var(--surface-hover)] transition-colors border-t border-[var(--line)] first:border-t-0"
                  >
                    <i className="w-2 h-2 rounded-full flex-shrink-0 bg-[var(--brand)]" />
                    <div className="flex-1 min-w-0">
                      <b className="block text-[13.5px] font-semibold text-[var(--fg)] truncate">
                        {pm.name}
                      </b>
                    </div>
                    <OverflowMenu
                      label={pm.name}
                      open={openMenu === `pm-${pm.id}`}
                      onOpenChange={(isOpen) => setOpenMenu(isOpen ? `pm-${pm.id}` : null)}
                      items={[
                        {
                          label: '编辑',
                          onSelect: () => setChannelDialog({ mode: 'edit', pm }),
                        },
                        'divider',
                        {
                          label: '删除',
                          tone: 'danger',
                          onSelect: () =>
                            setPendingDelete({ kind: 'channel', id: pm.id, name: pm.name }),
                        },
                      ]}
                    />
                  </div>
                ))}
              </div>
            )}
          </Panel>

          {/* Liability Channels Panel */}
          <Panel className="p-0 flex flex-col">
            <div className="flex items-center justify-between gap-2.5 px-[18px] py-3.5 border-b border-[var(--line)]">
              <h2 className="text-sm font-[650] text-[var(--fg)] flex items-baseline gap-2">
                负债渠道
                <span className="text-[11.5px] font-semibold text-[var(--fg-3)] num">
                  {liabilityChannels.length}
                </span>
              </h2>
              <Button
                variant="subtle"
                size="sm"
                onClick={() => {
                  setChannelDialog({ mode: 'create', type: 'liability' });
                  setOpenMenu(null);
                }}
              >
                <PlusIcon size={13} />
                添加
              </Button>
            </div>

            {loading ? (
              <SkeletonList />
            ) : liabilityChannels.length === 0 ? (
              <EmptyState
                title="暂无负债渠道"
                subtitle="用于记录还款与额度"
                action={{
                  label: '添加负债渠道',
                  onClick: () => {
                    setChannelDialog({ mode: 'create', type: 'liability' });
                    setOpenMenu(null);
                  },
                }}
              />
            ) : (
              <div className="p-1.5 flex flex-col">
                {liabilityChannels.map((pm) => (
                  <div
                    key={pm.id}
                    className="flex items-center gap-2.5 min-h-[52px] px-3 py-2 rounded-[10px] hover:bg-[var(--surface-hover)] transition-colors border-t border-[var(--line)] first:border-t-0"
                  >
                    <i className="w-2 h-2 rounded-full flex-shrink-0 bg-[var(--expense)]" />
                    <div className="flex-1 min-w-0">
                      <b className="block text-[13.5px] font-semibold text-[var(--fg)] truncate">
                        {pm.name}
                      </b>
                      <span className="block text-xs text-[var(--fg-3)] mt-0.5 num">
                        {pm.credit_limit > 0
                          ? `额度 ${formatMoney(pm.credit_limit, { sign: 'none' })}`
                          : '不设额度'}
                      </span>
                    </div>
                    <OverflowMenu
                      label={pm.name}
                      open={openMenu === `pm-${pm.id}`}
                      onOpenChange={(isOpen) => setOpenMenu(isOpen ? `pm-${pm.id}` : null)}
                      items={[
                        {
                          label: '编辑',
                          onSelect: () => setChannelDialog({ mode: 'edit', pm }),
                        },
                        'divider',
                        {
                          label: '删除',
                          tone: 'danger',
                          onSelect: () =>
                            setPendingDelete({ kind: 'channel', id: pm.id, name: pm.name }),
                        },
                      ]}
                    />
                  </div>
                ))}
              </div>
            )}
          </Panel>
        </div>
      )}

      {/* ==================== Layer 3: Tag Drawer ==================== */}
      {activeDrawerCategory &&
        createPortal(
          <div
            className="fixed inset-0 z-[1100] bg-[var(--overlay)] backdrop-blur-[4px] animate-fade
              flex justify-end items-stretch
              max-[639px]:items-end max-[639px]:p-3"
            onClick={closeDrawer}
          >
            <div
              role="dialog"
              aria-modal="true"
              aria-label={`${activeDrawerCategory.name} 细分标签`}
              onClick={(e) => e.stopPropagation()}
              className="w-full min-[640px]:w-[420px] max-h-[85dvh] min-[640px]:max-h-none min-[640px]:h-full
                bg-[var(--surface)] border border-[var(--line)] min-[640px]:border-y-0 min-[640px]:border-r-0 min-[640px]:border-l
                rounded-t-[16px] min-[640px]:rounded-none
                shadow-[var(--e4),inset_0_1px_0_var(--highlight-top)]
                flex flex-col overflow-hidden animate-slide-up min-[640px]:animate-slide"
            >
              {/* Drawer Header */}
              <div className="px-4 py-3 border-b border-[var(--line)] flex items-center justify-between flex-shrink-0 bg-[var(--surface-sunken)]">
                <div className="flex items-center gap-2 min-w-0">
                  <b className="text-sm font-[650] text-[var(--fg)] truncate">
                    {activeDrawerCategory.name}
                  </b>
                  {activeDrawerCategory.type === 'system' && (
                    <span className="inline-flex items-center gap-1 text-[11.5px] text-[var(--fg-3)]">
                      <LockIcon size={12} />
                      系统
                    </span>
                  )}
                  <Chip>{activeDrawerCategory.tags?.length || 0}</Chip>
                </div>
                <IconButton
                  ref={drawerCloseBtnRef}
                  label="关闭细分标签抽屉"
                  size={28}
                  onClick={closeDrawer}
                >
                  <CloseIcon size={15} />
                </IconButton>
              </div>

              {/* Drawer Body */}
              <div className="p-4 flex flex-col gap-3.5 overflow-y-auto flex-1 min-h-0">
                {activeDrawerCategory.type !== 'system' && (
                  <form
                    onSubmit={(e) => handleCreateTagInDrawer(activeDrawerCategory.id, e)}
                    className="flex items-center gap-2 min-w-0"
                  >
                    <input
                      ref={drawerNewTagInputRef}
                      type="text"
                      value={drawerNewTagName}
                      onChange={(e) => setDrawerNewTagName(e.target.value)}
                      placeholder="新标签名称"
                      className={`flex-1 min-w-0 ${INPUT_CLASS}`}
                    />
                    <Button
                      type="submit"
                      variant="primary"
                      size="sm"
                      disabled={isSubmittingTag}
                      className="flex-shrink-0"
                    >
                      {isSubmittingTag ? '添加中…' : '添加'}
                    </Button>
                  </form>
                )}

                {/* Tag List */}
                <div className="min-w-0">
                  {activeDrawerCategory.tags && activeDrawerCategory.tags.length > 0 ? (
                    activeDrawerCategory.tags.map((tag) => (
                      <div
                        key={tag.id}
                        className="flex items-center gap-2.5 py-2.5 border-t border-[var(--line)] first:border-t-0 min-w-0"
                      >
                        {editingTagId === tag.id ? (
                          <form
                            onSubmit={(e) => handleSaveTagRename(tag, e, activeDrawerCategory)}
                            className="flex items-center gap-2 w-full min-w-0 animate-fade"
                          >
                            <input
                              type="text"
                              autoFocus
                              value={editingTagName}
                              onChange={(e) => setEditingTagName(e.target.value)}
                              className={`flex-1 min-w-0 ${INPUT_CLASS}`}
                            />
                            <Button type="submit" variant="primary" size="sm">
                              保存
                            </Button>
                            <Button
                              variant="ghost"
                              size="sm"
                              onClick={() => {
                                setEditingTagId(null);
                                setEditingTagName('');
                              }}
                            >
                              取消
                            </Button>
                          </form>
                        ) : (
                          <>
                            <b className="flex-1 min-w-0 text-[13.5px] font-semibold text-[var(--fg)] truncate">
                              {tag.name}
                            </b>
                            {activeDrawerCategory.type !== 'system' && (
                              <OverflowMenu
                                label={tag.name}
                                open={openMenu === `tag-${tag.id}`}
                                onOpenChange={(isOpen) => setOpenMenu(isOpen ? `tag-${tag.id}` : null)}
                                items={[
                                  {
                                    label: '重命名',
                                    onSelect: () => {
                                      setEditingTagId(tag.id);
                                      setEditingTagName(tag.name);
                                    },
                                  },
                                  'divider',
                                  {
                                    label: '删除',
                                    tone: 'danger',
                                    onSelect: () =>
                                      setPendingDelete({ kind: 'tag', id: tag.id, name: tag.name }),
                                  },
                                ]}
                              />
                            )}
                          </>
                        )}
                      </div>
                    ))
                  ) : (
                    <div className="text-xs text-[var(--fg-muted)] py-8 text-center">
                      暂无细分标签
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>,
          document.body
        )}

      {/* Channel Dialog (Modal for Create & Edit) */}
      {channelDialog && (
        <ChannelDialog
          dialog={channelDialog}
          paymentMethods={paymentMethods}
          onClose={() => setChannelDialog(null)}
          onSave={handleSaveChannel}
        />
      )}

      {/* Single ConfirmDialog shared by category / channel / tag deletion */}
      <ConfirmDialog
        open={pendingDelete !== null}
        title={
          pendingDelete?.kind === 'category'
            ? '删除分类'
            : pendingDelete?.kind === 'channel'
            ? '删除渠道'
            : '删除标签'
        }
        description={`「${pendingDelete?.name ?? ''}」删除后不可恢复；若已被账单引用，删除将被拒绝。`}
        confirmLabel="删除"
        tone="danger"
        onConfirm={handleConfirmDelete}
        onCancel={() => setPendingDelete(null)}
      />
    </div>
  );
};

/* ============================== ChannelDialog ============================== */

interface ChannelDialogProps {
  dialog: { mode: 'create'; type: 'asset' | 'liability' } | { mode: 'edit'; pm: PaymentMethod };
  paymentMethods: PaymentMethod[];
  onClose: () => void;
  onSave: (name: string, type: 'asset' | 'liability', initialBal: number, creditLimit: number) => Promise<void>;
}

const ChannelDialog: FC<ChannelDialogProps> = ({ dialog, paymentMethods, onClose, onSave }) => {
  const isEdit = dialog.mode === 'edit';
  const pm = isEdit ? dialog.pm : null;
  const channelType = isEdit ? (dialog.pm.type || 'asset') : dialog.type;
  const isLiability = channelType === 'liability';

  const [name, setName] = useState(pm ? pm.name : '');
  const [balanceStr, setBalanceStr] = useState(pm && pm.initial_balance !== 0 ? String(pm.initial_balance) : '');
  const [limitStr, setLimitStr] = useState(pm && pm.credit_limit > 0 ? String(pm.credit_limit) : '');
  const [nameError, setNameError] = useState<string | null>(null);
  const [balanceError, setBalanceError] = useState<string | null>(null);
  const [limitError, setLimitError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const nameInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    nameInputRef.current?.focus();
  }, []);

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault();
    setNameError(null);
    setBalanceError(null);
    setLimitError(null);

    const trimmed = name.trim();
    if (!trimmed) {
      setNameError('请输入名称');
      nameInputRef.current?.focus();
      return;
    }

    const isDuplicate = paymentMethods.some(
      (p) => (!isEdit || p.id !== pm?.id) && p.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (isDuplicate) {
      setNameError('该渠道名称已存在');
      nameInputRef.current?.focus();
      return;
    }

    const parsedBal = balanceStr.trim() === '' ? 0 : parseFloat(balanceStr);
    if (isNaN(parsedBal) || parsedBal < 0) {
      setBalanceError(isLiability ? '初始欠款不能为负数' : '初始余额不能为负数');
      return;
    }

    let parsedLimit = 0;
    if (isLiability) {
      parsedLimit = limitStr.trim() === '' ? 0 : parseFloat(limitStr);
      if (isNaN(parsedLimit) || parsedLimit < 0) {
        setLimitError('授信额度不能为负数');
        return;
      }
    }

    setSubmitting(true);
    try {
      await onSave(trimmed, channelType, parsedBal, parsedLimit);
      onClose();
    } catch {
      // Keep dialog open on failure so user can retry or adjust input
    } finally {
      setSubmitting(false);
    }
  };

  const title = isEdit ? '编辑渠道' : isLiability ? '添加负债渠道' : '添加资产渠道';

  return createPortal(
    <div
      className="fixed inset-0 z-[1100] bg-[var(--overlay)] backdrop-blur-[4px] flex items-center justify-center p-3 animate-fade"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="channel-dialog-title"
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-[420px] bg-[var(--surface)] border border-[var(--line)] rounded-[var(--r-xl)] shadow-[var(--e4),inset_0_1px_0_var(--highlight-top)] animate-pop"
      >
        <div className="flex justify-between items-center px-[18px] py-3.5 border-b border-[var(--line)]">
          <b id="channel-dialog-title" className="text-[15px] font-semibold text-[var(--fg)]">
            {title}
          </b>
          <IconButton label="关闭" size={28} onClick={onClose}>
            <CloseIcon size={14} />
          </IconButton>
        </div>

        <form onSubmit={handleSubmit} className="p-[18px] flex flex-col gap-3.5">
          <div className="flex flex-col gap-1.5">
            <label htmlFor="channel-name" className="text-xs font-semibold text-[var(--fg-2)]">
              名称
            </label>
            <input
              id="channel-name"
              ref={nameInputRef}
              type="text"
              value={name}
              onChange={(e) => {
                setName(e.target.value);
                if (nameError) setNameError(null);
              }}
              placeholder={isLiability ? '招商信用卡' : '工商银行卡'}
              className={`w-full px-3 py-2 rounded-[var(--r-sm)] bg-[var(--surface)] border text-[16px] min-[640px]:text-[13.5px] text-[var(--fg)] outline-none transition-[border-color,box-shadow] duration-[var(--d1)] placeholder:text-[var(--fg-muted)] ${
                nameError
                  ? 'border-[var(--expense)]'
                  : 'border-[var(--line-strong)] focus:border-[var(--brand)] focus:shadow-[0_0_0_3px_var(--brand-soft)]'
              }`}
            />
            {nameError && <span className="text-xs text-[var(--expense-text)]">{nameError}</span>}
          </div>

          <div className="flex flex-col gap-1.5">
            <label htmlFor="channel-balance" className="text-xs font-semibold text-[var(--fg-2)]">
              {isLiability ? '初始欠款' : '初始余额'}
            </label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs text-[var(--fg-3)] pointer-events-none">
                ¥
              </span>
              <input
                id="channel-balance"
                type="text"
                inputMode="decimal"
                value={balanceStr}
                onChange={(e) => {
                  setBalanceStr(e.target.value);
                  if (balanceError) setBalanceError(null);
                }}
                placeholder="0.00"
                className={`w-full pl-7 pr-3 py-2 rounded-[var(--r-sm)] bg-[var(--surface)] border text-[16px] min-[640px]:text-[13.5px] text-[var(--fg)] outline-none transition-[border-color,box-shadow] duration-[var(--d1)] placeholder:text-[var(--fg-muted)] ${
                  balanceError
                    ? 'border-[var(--expense)]'
                    : 'border-[var(--line-strong)] focus:border-[var(--brand)] focus:shadow-[0_0_0_3px_var(--brand-soft)]'
                }`}
              />
            </div>
            {balanceError && <span className="text-xs text-[var(--expense-text)]">{balanceError}</span>}
          </div>

          {isLiability && (
            <div className="flex flex-col gap-1.5">
              <label htmlFor="channel-limit" className="text-xs font-semibold text-[var(--fg-2)]">
                授信额度
              </label>
              <div className="relative">
                <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs text-[var(--fg-3)] pointer-events-none">
                  ¥
                </span>
                <input
                  id="channel-limit"
                  type="text"
                  inputMode="decimal"
                  value={limitStr}
                  onChange={(e) => {
                    setLimitStr(e.target.value);
                    if (limitError) setLimitError(null);
                  }}
                  placeholder="不设额度"
                  className={`w-full pl-7 pr-3 py-2 rounded-[var(--r-sm)] bg-[var(--surface)] border text-[16px] min-[640px]:text-[13.5px] text-[var(--fg)] outline-none transition-[border-color,box-shadow] duration-[var(--d1)] placeholder:text-[var(--fg-muted)] ${
                    limitError
                      ? 'border-[var(--expense)]'
                      : 'border-[var(--line-strong)] focus:border-[var(--brand)] focus:shadow-[0_0_0_3px_var(--brand-soft)]'
                  }`}
                />
              </div>
              {limitError && <span className="text-xs text-[var(--expense-text)]">{limitError}</span>}
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2 border-t border-[var(--line)]">
            <Button variant="ghost" size="md" onClick={onClose} disabled={submitting}>
              取消
            </Button>
            <Button type="submit" variant="primary" size="md" disabled={submitting}>
              {submitting ? '保存中…' : '保存'}
            </Button>
          </div>
        </form>
      </div>
    </div>,
    document.body
  );
};
