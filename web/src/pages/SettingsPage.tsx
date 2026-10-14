import { useState, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import type { FC, FormEvent, ReactNode } from 'react';
import { Category, PaymentMethod, Tag } from '../lib/api';
import { formatMoney } from '../lib/format.ts';
import { Panel, SegmentedControl, IconButton, Button, Chip, EmptyState, ConfirmDialog } from '../components/primitives';
import {
  PlusIcon,
  ChevronUpIcon,
  ChevronDownIcon,
  TrashIcon,
  EditIcon,
  CloseIcon,
} from '../components/Icons';

interface SettingsPageProps {
  categories: Category[];
  paymentMethods: PaymentMethod[];
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

const INPUT_CLASS =
  'px-3 py-1.5 rounded-[var(--r-sm)] bg-[var(--surface)] border border-[var(--line-strong)] ' +
  'text-xs text-[var(--fg)] outline-none placeholder:text-[var(--fg-muted)] ' +
  'focus:border-[var(--brand)] focus:shadow-[0_0_0_3px_var(--brand-soft)] ' +
  'transition-[border-color,box-shadow] duration-[var(--d1)]';

export const SettingsPage: FC<SettingsPageProps> = ({
  categories,
  paymentMethods,
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
  const [activeTab, setActiveTab] = useState<'categories' | 'paymentMethods'>('categories');

  // Channel inline add states
  const [showAddAssetInput, setShowAddAssetInput] = useState(false);
  const [newAssetName, setNewAssetName] = useState('');
  const [newAssetBalance, setNewAssetBalance] = useState('');

  const [showAddLiabilityInput, setShowAddLiabilityInput] = useState(false);
  const [newLiabilityName, setNewLiabilityName] = useState('');
  const [newLiabilityDebt, setNewLiabilityDebt] = useState('');
  const [newLiabilityLimit, setNewLiabilityLimit] = useState('');

  // Channel inline edit states
  const [editingPmId, setEditingPmId] = useState<number | null>(null);
  const [editingPmName, setEditingPmName] = useState('');
  const [editingPmInitBal, setEditingPmInitBal] = useState('');
  const [editingPmLimit, setEditingPmLimit] = useState('');
  const [editingPmType, setEditingPmType] = useState<'asset' | 'liability'>('asset');

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

  // ESC key listener to close drawer or editing state; yields to ConfirmDialog when open
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (pendingDelete !== null) {
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
        } else if (editingPmId !== null) {
          setEditingPmId(null);
        } else if (showAddCatInput) {
          setShowAddCatInput(false);
          setNewCatName('');
        } else if (showAddAssetInput) {
          setShowAddAssetInput(false);
          setNewAssetName('');
          setNewAssetBalance('');
        } else if (showAddLiabilityInput) {
          setShowAddLiabilityInput(false);
          setNewLiabilityName('');
          setNewLiabilityDebt('');
          setNewLiabilityLimit('');
        }
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [
    pendingDelete,
    activeDrawerCategory,
    editingTagId,
    editingCatId,
    editingPmId,
    showAddCatInput,
    showAddAssetInput,
    showAddLiabilityInput,
  ]);

  const handleCreateAssetChannel = async (e: FormEvent) => {
    e.preventDefault();
    const trimmed = newAssetName.trim();
    if (!trimmed) return;
    if (paymentMethods.some((pm) => pm.name.toLowerCase() === trimmed.toLowerCase())) {
      onToast?.('error', '该渠道名称已存在');
      return;
    }
    const balance = parseFloat(newAssetBalance) || 0;
    if (balance < 0) {
      onToast?.('error', '初始余额不能为负数');
      return;
    }
    try {
      await onAddPaymentMethod(trimmed, 'asset', balance, 0);
      setNewAssetName('');
      setNewAssetBalance('');
      setShowAddAssetInput(false);
    } catch {
      // Handled in parent
    }
  };

  const handleCreateLiabilityChannel = async (e: FormEvent) => {
    e.preventDefault();
    const trimmed = newLiabilityName.trim();
    if (!trimmed) return;
    if (paymentMethods.some((pm) => pm.name.toLowerCase() === trimmed.toLowerCase())) {
      onToast?.('error', '该渠道名称已存在');
      return;
    }
    const debt = parseFloat(newLiabilityDebt) || 0;
    const limit = parseFloat(newLiabilityLimit) || 0;
    if (debt < 0) {
      onToast?.('error', '初始欠款不能为负数');
      return;
    }
    if (limit < 0) {
      onToast?.('error', '授信额度不能为负数');
      return;
    }
    try {
      await onAddPaymentMethod(trimmed, 'liability', debt, limit);
      setNewLiabilityName('');
      setNewLiabilityDebt('');
      setNewLiabilityLimit('');
      setShowAddLiabilityInput(false);
    } catch {
      // Handled in parent
    }
  };

  const handleStartEditPm = (pm: PaymentMethod) => {
    setEditingPmId(pm.id);
    setEditingPmName(pm.name);
    setEditingPmInitBal(String(pm.initial_balance));
    setEditingPmLimit(String(pm.credit_limit));
    setEditingPmType(pm.type || 'asset');
  };

  const handleSavePmEdit = async (pm: PaymentMethod, e: FormEvent) => {
    e.preventDefault();
    const trimmed = editingPmName.trim();
    if (!trimmed) {
      onToast?.('error', '渠道名称不能为空');
      return;
    }
    const isDuplicate = paymentMethods.some(
      (p) => p.id !== pm.id && p.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (isDuplicate) {
      onToast?.('error', '该渠道名称已存在');
      return;
    }
    const initBal = parseFloat(editingPmInitBal) || 0;
    const limit = parseFloat(editingPmLimit) || 0;
    if (initBal < 0) {
      onToast?.('error', editingPmType === 'liability' ? '初始欠款不能为负数' : '初始余额不能为负数');
      return;
    }
    if (limit < 0) {
      onToast?.('error', '授信额度不能为负数');
      return;
    }
    try {
      await onUpdatePaymentMethod(pm.id, trimmed, pm.sort_order, editingPmType, initBal, limit);
      setEditingPmId(null);
    } catch {
      // Keep edit state open
    }
  };

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

  // Derive asset and liability channels
  const assetChannels = paymentMethods.filter((pm) => pm.type === 'asset' || !pm.type);
  const liabilityChannels = paymentMethods.filter((pm) => pm.type === 'liability');

  const channelRow = (pm: PaymentMethod) => {
    if (editingPmId === pm.id) {
      return (
        <form
          key={pm.id}
          onSubmit={(e) => handleSavePmEdit(pm, e)}
          className="col-span-1 p-3 rounded-[var(--r-md)] border border-[var(--brand)] bg-[var(--surface)] flex flex-col gap-2"
        >
          <input
            type="text"
            autoFocus
            value={editingPmName}
            onChange={(e) => setEditingPmName(e.target.value)}
            placeholder="渠道名称"
            className="w-full px-2.5 py-1 rounded-[var(--r-sm)] bg-[var(--surface-sunken)] border border-[var(--line-strong)] text-xs text-[var(--fg)] outline-none focus:border-[var(--brand)]"
          />
          <div className={editingPmType === 'liability' ? 'grid grid-cols-2 gap-2' : ''}>
            <div className={editingPmType === 'liability' ? 'flex flex-col gap-0.5' : 'flex items-center gap-1.5'}>
              <span className={editingPmType === 'liability' ? 'text-[10px] text-[var(--fg-3)]' : 'text-[11px] text-[var(--fg-3)] flex-shrink-0'}>
                {editingPmType === 'liability' ? '初始欠款' : '初始余额'}
              </span>
              <input
                type="number"
                step="0.01"
                min="0"
                value={editingPmInitBal}
                onChange={(e) => setEditingPmInitBal(e.target.value)}
                className="w-full px-2 py-1 rounded-[var(--r-sm)] bg-[var(--surface-sunken)] border border-[var(--line-strong)] text-xs text-[var(--fg)] outline-none focus:border-[var(--brand)]"
              />
            </div>
            {editingPmType === 'liability' && (
              <div className="flex flex-col gap-0.5">
                <span className="text-[10px] text-[var(--fg-3)]">授信额度</span>
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={editingPmLimit}
                  onChange={(e) => setEditingPmLimit(e.target.value)}
                  className="w-full px-2 py-1 rounded-[var(--r-sm)] bg-[var(--surface-sunken)] border border-[var(--line-strong)] text-xs text-[var(--fg)] outline-none focus:border-[var(--brand)]"
                />
              </div>
            )}
          </div>
          <div className="flex items-center gap-1.5 justify-end mt-1">
            <Button type="submit" variant="primary" size="sm">保存</Button>
            <Button variant="subtle" size="sm" onClick={() => setEditingPmId(null)}>取消</Button>
          </div>
        </form>
      );
    }

    const isLiability = (pm.type || 'asset') === 'liability';
    return (
      <div
        key={pm.id}
        className="flex items-center gap-2.5 py-2.5 border-t border-[var(--line)] first:border-t-0"
      >
        <i
          className="w-[7px] h-[7px] rounded-full flex-shrink-0"
          style={{ background: isLiability ? 'var(--expense)' : 'var(--brand)' }}
        />
        <div className="flex-1 min-w-0">
          <b className="block text-[13.5px] font-semibold text-[var(--fg)] truncate">{pm.name}</b>
          <span className="block text-xs text-[var(--fg-3)] mt-px num">
            {isLiability
              ? `额度 ${pm.credit_limit > 0 ? formatMoney(pm.credit_limit, { sign: 'none' }) : '不限'} · 初始欠款 ${formatMoney(pm.initial_balance, { sign: 'none' })}`
              : `初始余额 ${formatMoney(pm.initial_balance, { sign: 'none' })}`}
          </span>
        </div>
        {/* Actions always visible — mobile has no hover */}
        <IconButton label={`编辑渠道 ${pm.name}`} size={28} onClick={() => handleStartEditPm(pm)}>
          <EditIcon size={13} />
        </IconButton>
        <IconButton
          label={`删除渠道 ${pm.name}`}
          tone="danger"
          size={28}
          onClick={() => setPendingDelete({ kind: 'channel', id: pm.id, name: pm.name })}
        >
          <TrashIcon size={13} />
        </IconButton>
      </div>
    );
  };

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
          onChange={(key) => setActiveTab(key as 'categories' | 'paymentMethods')}
          ariaLabel="设置分区"
          className="[&>button]:px-3.5"
        />
      </div>

      {/* ==================== Section 1: Categories & Tags ==================== */}
      {activeTab === 'categories' && (
        <div className="flex flex-col gap-4">
          <PanelCard
            title={`${categoryTypeTab === 'income' ? '收入分类' : '支出分类'}`}
            count={currentCategories.length}
            action={
              !showAddCatInput ? (
                <Button variant="subtle" size="sm" onClick={() => setShowAddCatInput(true)}>
                  <PlusIcon size={13} />
                  新增{categoryTypeTab === 'income' ? '收入分类' : '支出分类'}
                </Button>
              ) : undefined
            }
          >
            {/* Secondary type switch */}
            <div className="mb-1">
              <SegmentedControl
                items={[
                  { key: 'expense', label: `支出分类 (${expenseCategories.length})` },
                  { key: 'income', label: `收入分类 (${incomeCategories.length})` },
                ]}
                value={categoryTypeTab}
                onChange={(key) => {
                  setCategoryTypeTab(key as 'expense' | 'income');
                  setShowAddCatInput(false);
                }}
                ariaLabel="分类类型"
                className="[&>button]:px-3 [&>button]:text-xs w-fit"
              />
            </div>

            {/* Inline Creation Form */}
            {showAddCatInput && (
              <form
                onSubmit={handleCreateCategory}
                className="flex items-center gap-2 p-3 bg-[var(--surface-sunken)] rounded-[var(--r-md)] border border-[var(--line)] animate-fade"
              >
                <input
                  type="text"
                  autoFocus
                  value={newCatName}
                  onChange={(e) => setNewCatName(e.target.value)}
                  placeholder={categoryTypeTab === 'income' ? '输入收入分类名称 (如：职业收入、理财利息)' : '输入支出分类名称 (如：数码科技、宠物养护)'}
                  className={`flex-1 ${INPUT_CLASS}`}
                />
                <Button type="submit" variant="primary" size="sm">确定</Button>
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
            )}

            {/* Hairline Category List */}
            {currentCategories.length === 0 ? (
              <EmptyState
                title={`暂无${categoryTypeTab === 'income' ? '收入分类' : '支出分类'}`}
                subtitle="创建第一个分类后开始记账"
                action={{ label: '立即新增', onClick: () => setShowAddCatInput(true) }}
              />
            ) : (
              currentCategories.map((cat, index) => (
                <div key={cat.id} className="py-2.5 border-t border-[var(--line)] first:border-t-0">
                  {editingCatId === cat.id ? (
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
                        <Button type="submit" variant="primary" size="sm">保存</Button>
                        <Button variant="subtle" size="sm" onClick={() => setEditingCatId(null)}>取消</Button>
                      </div>
                    </form>
                  ) : (
                    <div className="flex items-center gap-2.5">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <b className="text-[13.5px] font-semibold text-[var(--fg)] truncate">{cat.name}</b>
                          <Chip>{cat.tags?.length || 0} 个细分标签</Chip>
                        </div>
                      </div>
                      <Button
                        variant="subtle"
                        size="sm"
                        onClick={(e) => openDrawer(cat.id, e.currentTarget)}
                      >
                        <EditIcon size={12} />
                        {cat.type === 'system' ? '查看标签' : '管理标签'}
                      </Button>
                      {cat.type !== 'system' && (
                        <>
                          <IconButton
                            label={`上移 ${cat.name}`}
                            size={28}
                            disabled={index === 0}
                            onClick={() => handleMoveCategory(index, 'up')}
                          >
                            <ChevronUpIcon size={13} />
                          </IconButton>
                          <IconButton
                            label={`下移 ${cat.name}`}
                            size={28}
                            disabled={index === currentCategories.length - 1}
                            onClick={() => handleMoveCategory(index, 'down')}
                          >
                            <ChevronDownIcon size={13} />
                          </IconButton>
                          <IconButton
                            label={`编辑 ${cat.name}`}
                            size={28}
                            onClick={() => {
                              setEditingCatId(cat.id);
                              setEditingCatName(cat.name);
                              setEditingCatType(cat.type === 'income' ? 'income' : 'expense');
                            }}
                          >
                            <EditIcon size={13} />
                          </IconButton>
                          <IconButton
                            label={`删除 ${cat.name}`}
                            tone="danger"
                            size={28}
                            onClick={() => setPendingDelete({ kind: 'category', id: cat.id, name: cat.name })}
                          >
                            <TrashIcon size={13} />
                          </IconButton>
                        </>
                      )}
                    </div>
                  )}
                </div>
              ))
            )}

            {/* System Categories */}
            {systemCategories.length > 0 && (
              <div className="mt-2 pt-4 border-t border-[var(--line)] flex flex-col gap-2">
                <span className="text-xs font-semibold text-[var(--fg-3)] px-0.5">系统内置分类</span>
                {systemCategories.map((cat) => (
                  <div key={cat.id} className="flex items-center gap-2.5 py-1">
                    <div className="flex-1 min-w-0 flex items-center gap-2">
                      <b className="text-[13.5px] font-semibold text-[var(--fg)] truncate">{cat.name}</b>
                      <Chip tone="brand">系统内置</Chip>
                      <Chip>{cat.tags?.length || 0} 个内置标签</Chip>
                    </div>
                    <Button
                      variant="subtle"
                      size="sm"
                      onClick={(e) => openDrawer(cat.id, e.currentTarget)}
                    >
                      <EditIcon size={12} />
                      查看标签
                    </Button>
                  </div>
                ))}
              </div>
            )}
          </PanelCard>
        </div>
      )}

      {/* ==================== Section 2: Channels & Accounts ==================== */}
      {activeTab === 'paymentMethods' && (
        <div className="flex flex-col gap-4">
          <PanelCard
            title="资产渠道"
            count={assetChannels.length}
            action={
              !showAddAssetInput ? (
                <Button variant="subtle" size="sm" onClick={() => setShowAddAssetInput(true)}>
                  <PlusIcon size={13} />
                  添加资产渠道
                </Button>
              ) : undefined
            }
          >
            {showAddAssetInput && (
              <form
                onSubmit={handleCreateAssetChannel}
                className="flex flex-wrap items-center gap-2 p-3 bg-[var(--surface-sunken)] rounded-[var(--r-md)] border border-[var(--line)] animate-fade"
              >
                <input
                  type="text"
                  autoFocus
                  value={newAssetName}
                  onChange={(e) => setNewAssetName(e.target.value)}
                  placeholder="渠道名称 (如: 工商银行卡、微信零钱)"
                  className={`flex-2 min-w-[150px] ${INPUT_CLASS}`}
                />
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={newAssetBalance}
                  onChange={(e) => setNewAssetBalance(e.target.value)}
                  placeholder="初始余额 (元)"
                  className={`flex-1 min-w-[110px] ${INPUT_CLASS}`}
                />
                <Button type="submit" variant="primary" size="sm">保存</Button>
                <Button
                  variant="subtle"
                  size="sm"
                  onClick={() => {
                    setShowAddAssetInput(false);
                    setNewAssetName('');
                    setNewAssetBalance('');
                  }}
                >
                  取消
                </Button>
              </form>
            )}

            <div className="grid grid-cols-1 min-[640px]:grid-cols-2">
              {assetChannels.length === 0 ? (
                <div className="col-span-full">
                  <EmptyState
                    title="暂无资产渠道"
                    subtitle="添加后用于记录支出与收入"
                    action={{ label: '添加资产渠道', onClick: () => setShowAddAssetInput(true) }}
                  />
                </div>
              ) : (
                assetChannels.map(channelRow)
              )}
            </div>
          </PanelCard>

          <PanelCard
            title="负债渠道"
            count={liabilityChannels.length}
            action={
              !showAddLiabilityInput ? (
                <Button variant="subtle" size="sm" onClick={() => setShowAddLiabilityInput(true)}>
                  <PlusIcon size={13} />
                  添加负债渠道
                </Button>
              ) : undefined
            }
          >
            {showAddLiabilityInput && (
              <form
                onSubmit={handleCreateLiabilityChannel}
                className="flex flex-wrap items-center gap-2 p-3 bg-[var(--surface-sunken)] rounded-[var(--r-md)] border border-[var(--line)] animate-fade"
              >
                <input
                  type="text"
                  autoFocus
                  value={newLiabilityName}
                  onChange={(e) => setNewLiabilityName(e.target.value)}
                  placeholder="渠道名称 (如: 招商信用卡、花呗)"
                  className={`flex-2 min-w-[150px] ${INPUT_CLASS}`}
                />
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={newLiabilityDebt}
                  onChange={(e) => setNewLiabilityDebt(e.target.value)}
                  placeholder="初始欠款 (元)"
                  className={`flex-1 min-w-[100px] ${INPUT_CLASS}`}
                />
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={newLiabilityLimit}
                  onChange={(e) => setNewLiabilityLimit(e.target.value)}
                  placeholder="授信额度 (0为不限)"
                  className={`flex-1 min-w-[110px] ${INPUT_CLASS}`}
                />
                <Button type="submit" variant="primary" size="sm">保存</Button>
                <Button
                  variant="subtle"
                  size="sm"
                  onClick={() => {
                    setShowAddLiabilityInput(false);
                    setNewLiabilityName('');
                    setNewLiabilityDebt('');
                    setNewLiabilityLimit('');
                  }}
                >
                  取消
                </Button>
              </form>
            )}

            <div className="grid grid-cols-1 min-[640px]:grid-cols-2">
              {liabilityChannels.length === 0 ? (
                <div className="col-span-full">
                  <EmptyState
                    title="暂无负债渠道"
                    subtitle="添加后用于记录还款与额度"
                    action={{ label: '添加负债渠道', onClick: () => setShowAddLiabilityInput(true) }}
                  />
                </div>
              ) : (
                liabilityChannels.map(channelRow)
              )}
            </div>
          </PanelCard>
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
                    {activeDrawerCategory.name} · 细分标签
                  </b>
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
                {activeDrawerCategory.type !== 'system' ? (
                  <form onSubmit={(e) => handleCreateTagInDrawer(activeDrawerCategory.id, e)} className="flex items-center gap-2 min-w-0">
                    <input
                      ref={drawerNewTagInputRef}
                      type="text"
                      value={drawerNewTagName}
                      onChange={(e) => setDrawerNewTagName(e.target.value)}
                      placeholder="添加细分标签 (如：午餐、地铁)"
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
                ) : (
                  <div className="p-3 rounded-[var(--r-sm)] bg-[var(--brand-soft)] border border-[var(--brand-line)] text-xs text-[var(--brand-text)]">
                    系统分类标签由底层调度引擎固定保护，不可增删改
                  </div>
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
                            <Button type="submit" variant="primary" size="sm">保存</Button>
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
                            <b className="flex-1 min-w-0 text-[13.5px] font-semibold text-[var(--fg)] truncate">{tag.name}</b>
                            {activeDrawerCategory.type !== 'system' ? (
                              <>
                                <IconButton
                                  label={`重命名 ${tag.name}`}
                                  size={28}
                                  onClick={() => {
                                    setEditingTagId(tag.id);
                                    setEditingTagName(tag.name);
                                  }}
                                >
                                  <EditIcon size={13} />
                                </IconButton>
                                <IconButton
                                  label={`删除 ${tag.name}`}
                                  tone="danger"
                                  size={28}
                                  onClick={() => setPendingDelete({ kind: 'tag', id: tag.id, name: tag.name })}
                                >
                                  <TrashIcon size={13} />
                                </IconButton>
                              </>
                            ) : (
                              <Chip tone="brand">系统固定</Chip>
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

              {/* Drawer Footer */}
              <div className="px-4 py-3 border-t border-[var(--line)] flex justify-end flex-shrink-0">
                <Button
                  variant="subtle"
                  size="sm"
                  onClick={closeDrawer}
                >
                  完成
                </Button>
              </div>
            </div>
          </div>,
          document.body
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

/* Local panel card with head + hairline content (surface comes from the shared Panel) */
const PanelCard: FC<{ title: string; count?: number; action?: ReactNode; children: ReactNode }> = ({
  title,
  count,
  action,
  children,
}) => (
  <Panel className="p-[18px] flex flex-col gap-3">
    <div className="flex items-center justify-between gap-2.5">
      <div className="flex items-baseline gap-2">
        <b className="text-sm font-[650] text-[var(--fg)]">{title}</b>
        {count !== undefined && <span className="text-[11.5px] font-semibold text-[var(--fg-3)] num">{count}</span>}
      </div>
      {action}
    </div>
    {children}
  </Panel>
);
