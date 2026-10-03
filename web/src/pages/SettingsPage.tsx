import { useState, useEffect } from 'react';
import type { FC, FormEvent } from 'react';
import { Category, PaymentMethod, Tag } from '../lib/api';
import {
  PlusIcon,
  ChevronUpIcon,
  ChevronDownIcon,
  MoreVerticalIcon,
  TrashIcon,
  EditIcon,
  CloseIcon,
} from '../components/Icons';

interface SettingsPageProps {
  categories: Category[];
  paymentMethods: PaymentMethod[];
  onAddPaymentMethod: (name: string, type: 'asset' | 'liability', initialBalance: number, creditLimit: number) => Promise<void>;
  onUpdatePaymentMethod?: (id: number, name: string, sort_order: number, type: 'asset' | 'liability', initialBalance: number, creditLimit: number) => Promise<void>;
  onDeletePaymentMethod: (id: number) => Promise<void>;
  onAddCategory: (name: string) => Promise<void>;
  onUpdateCategory: (id: number, name: string, sort_order: number) => Promise<void>;
  onReorderCategories?: (updates: { id: number; name: string; sort_order: number }[]) => Promise<void>;
  onDeleteCategory: (id: number) => Promise<void>;
  onAddTag: (categoryId: number, name: string) => Promise<void>;
  onUpdateTag: (id: number, name: string, sort_order: number) => Promise<void>;
  onDeleteTag: (id: number) => Promise<void>;
  onToast?: (type: 'success' | 'error' | 'info', message: string) => void;
}

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

  // Category inline add state
  const [newCatName, setNewCatName] = useState('');
  const [showAddCatInput, setShowAddCatInput] = useState(false);

  // Drawer & Tag state (Layer 3 Drawer container bound to SSOT activeCategoryId)
  const [activeDrawerCategoryId, setActiveDrawerCategoryId] = useState<number | null>(null);
  const [drawerNewTagName, setDrawerNewTagName] = useState('');

  // Dropdown context menu state for category row
  const [openCatMenuId, setOpenCatMenuId] = useState<number | null>(null);

  // Inline rename states
  const [editingCatId, setEditingCatId] = useState<number | null>(null);
  const [editingCatName, setEditingCatName] = useState('');

  const [editingTagId, setEditingTagId] = useState<number | null>(null);
  const [editingTagName, setEditingTagName] = useState('');

  // Close context menu on outside click
  useEffect(() => {
    const handleDocumentClick = () => {
      setOpenCatMenuId(null);
    };
    document.addEventListener('click', handleDocumentClick);
    return () => document.removeEventListener('click', handleDocumentClick);
  }, []);

  // ESC key listener to close drawer or editing state
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        if (editingTagId !== null) {
          setEditingTagId(null);
        } else if (activeDrawerCategoryId !== null) {
          setActiveDrawerCategoryId(null);
          setDrawerNewTagName('');
        } else if (editingCatId !== null) {
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
    activeDrawerCategoryId,
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
    if (onUpdatePaymentMethod) {
      try {
        await onUpdatePaymentMethod(pm.id, trimmed, pm.sort_order, editingPmType, initBal, limit);
        setEditingPmId(null);
      } catch {
        // Keep edit state open
      }
    }
  };

  const handleCreateCategory = async (e: FormEvent) => {
    e.preventDefault();
    if (!newCatName.trim()) return;
    await onAddCategory(newCatName.trim());
    setNewCatName('');
    setShowAddCatInput(false);
  };

  const handleCreateTagInDrawer = async (categoryId: number, e: FormEvent) => {
    e.preventDefault();
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

    await onAddTag(categoryId, trimmed);
    setDrawerNewTagName('');
  };

  const handleMoveCategory = async (index: number, direction: 'up' | 'down') => {
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= categories.length) return;

    const itemA = categories[index];
    const itemB = categories[targetIndex];

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
      if (onReorderCategories) {
        await onReorderCategories([
          { id: itemA.id, name: itemA.name, sort_order: orderForA },
          { id: itemB.id, name: itemB.name, sort_order: orderForB },
        ]);
      } else {
        await Promise.all([
          onUpdateCategory(itemA.id, itemA.name, orderForA),
          onUpdateCategory(itemB.id, itemB.name, orderForB),
        ]);
      }
    } catch {
      // Toast and refresh handled in parent
    }
  };

  const handleSaveCatRename = async (cat: Category, e: FormEvent) => {
    e.preventDefault();
    const trimmed = editingCatName.trim();
    if (!trimmed || trimmed === cat.name) {
      setEditingCatId(null);
      return;
    }

    // Pre-check duplicate in sibling categories
    const isDuplicate = categories.some(
      (c) => c.id !== cat.id && c.name.toLowerCase() === trimmed.toLowerCase()
    );
    if (isDuplicate) {
      onToast?.('error', '该消费类型已存在');
      return;
    }

    try {
      await onUpdateCategory(cat.id, trimmed, cat.sort_order);
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

  // Derive active category directly from SSOT
  const activeDrawerCategory = categories.find((c) => c.id === activeDrawerCategoryId);

  // Derive asset and liability channels
  const assetChannels = paymentMethods.filter((pm) => pm.type === 'asset' || !pm.type);
  const liabilityChannels = paymentMethods.filter((pm) => pm.type === 'liability');

  return (
    <div className="w-full max-w-[900px] flex flex-col gap-5 animate-fade-in pb-16">
      {/* Header with Title and Segmented Tabs */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <h3 className="text-xl font-bold tracking-tight text-[var(--color-neutral-fg-1)]">
          设置
        </h3>

        {/* 2-Section Segmented Capsule */}
        <div className="bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] rounded-xl p-1 inline-flex items-center gap-1 shadow-[var(--shadow-card)]">
          <button
            type="button"
            onClick={() => setActiveTab('categories')}
            className={`px-3.5 py-1.5 rounded-lg text-xs font-medium cursor-pointer transition-all duration-150 ${
              activeTab === 'categories'
                ? 'bg-[var(--color-brand)] text-white font-semibold shadow-sm'
                : 'text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)]'
            }`}
          >
            分类与标签
          </button>
          <button
            type="button"
            onClick={() => setActiveTab('paymentMethods')}
            className={`px-3.5 py-1.5 rounded-lg text-xs font-medium cursor-pointer transition-all duration-150 ${
              activeTab === 'paymentMethods'
                ? 'bg-[var(--color-brand)] text-white font-semibold shadow-sm'
                : 'text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)]'
            }`}
          >
            渠道与账户
          </button>
        </div>
      </div>

      {/* Section 1: Categories & Tags Taxonomy */}
      {activeTab === 'categories' && (
        <div className="bg-[var(--color-card-bg)] rounded-2xl border border-[var(--color-neutral-stroke)] p-5.5 shadow-[var(--shadow-card)] flex flex-col gap-4">
          <div className="flex items-center justify-between">
            <h4 className="text-base font-semibold text-[var(--color-neutral-fg-1)]">
              消费类型
            </h4>
            {!showAddCatInput && (
              <button
                type="button"
                onClick={() => setShowAddCatInput(true)}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--color-hover-bg)] hover:bg-[var(--color-brand-light)] hover:text-[var(--color-brand)] text-xs font-semibold text-[var(--color-neutral-fg-2)] cursor-pointer transition-colors"
              >
                <PlusIcon size={14} />
                <span>新增类型</span>
              </button>
            )}
          </div>

          {/* Lightweight Inline Creation Form */}
          {showAddCatInput && (
            <form
              onSubmit={handleCreateCategory}
              className="flex items-center gap-2 p-3 bg-[var(--color-hover-bg)] rounded-xl border border-[var(--color-neutral-stroke)] animate-fade-in"
            >
              <input
                type="text"
                autoFocus
                value={newCatName}
                onChange={(e) => setNewCatName(e.target.value)}
                placeholder="输入类型名称 (如：数码科技、宠物养护)"
                className="flex-1 px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
              />
              <button
                type="submit"
                className="px-3.5 py-1.5 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer"
              >
                确定
              </button>
              <button
                type="button"
                onClick={() => {
                  setShowAddCatInput(false);
                  setNewCatName('');
                }}
                className="px-3 py-1.5 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-card-bg)] cursor-pointer"
              >
                取消
              </button>
            </form>
          )}

          {/* Clean Category List */}
          <div className="flex flex-col gap-2.5">
            {categories.map((cat, index) => (
              <div
                key={cat.id}
                className="group border border-[var(--color-neutral-stroke)] rounded-xl p-3 sm:px-4 bg-[var(--color-subtle-bg)] hover:bg-[var(--color-card-bg)] hover:border-[var(--color-neutral-stroke-strong)] flex flex-col gap-2 transition-all relative"
              >
                {/* Inline Category Rename Mode */}
                {editingCatId === cat.id ? (
                  <form
                    onSubmit={(e) => handleSaveCatRename(cat, e)}
                    className="flex items-center gap-2 animate-fade-in"
                  >
                    <input
                      type="text"
                      autoFocus
                      value={editingCatName}
                      onChange={(e) => setEditingCatName(e.target.value)}
                      className="flex-1 px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-brand)] text-xs text-[var(--color-neutral-fg-1)] outline-none"
                    />
                    <button
                      type="submit"
                      className="px-3 py-1.5 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer"
                    >
                      保存
                    </button>
                    <button
                      type="button"
                      onClick={() => setEditingCatId(null)}
                      className="px-2.5 py-1.5 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-card-bg)] cursor-pointer"
                    >
                      取消
                    </button>
                  </form>
                ) : (
                  <div className="flex items-center justify-between">
                    {/* Left: Category info */}
                    <div className="flex items-center gap-2.5 min-w-0">
                      <span className="text-sm font-semibold text-[var(--color-neutral-fg-1)] truncate">
                        {cat.name}
                      </span>
                      <span className="text-[11px] font-medium px-2 py-0.5 rounded-full bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] text-[var(--color-neutral-fg-3)] flex-shrink-0">
                        {cat.tags?.length || 0} 个细分标签
                      </span>
                    </div>

                    {/* Right: Actions */}
                    <div className="flex items-center gap-1.5">
                      {/* Open Tag Management Drawer Button */}
                      <button
                        type="button"
                        onClick={() => {
                          setActiveDrawerCategoryId(cat.id);
                          setDrawerNewTagName('');
                          setEditingTagId(null);
                        }}
                        className="flex items-center gap-1 px-2.5 py-1 rounded-lg bg-[var(--color-card-bg)] hover:bg-[var(--color-brand-light)] hover:text-[var(--color-brand)] border border-[var(--color-neutral-stroke)] text-xs font-medium text-[var(--color-neutral-fg-2)] cursor-pointer transition-colors"
                      >
                        <EditIcon size={12} />
                        <span>管理标签</span>
                      </button>

                      {/* Move Up */}
                      <button
                        type="button"
                        title="上移类型"
                        disabled={index === 0}
                        onClick={() => handleMoveCategory(index, 'up')}
                        className="w-7 h-7 rounded-md flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] disabled:opacity-20 disabled:cursor-not-allowed cursor-pointer transition-colors"
                      >
                        <ChevronUpIcon size={13} />
                      </button>

                      {/* Move Down */}
                      <button
                        type="button"
                        title="下移类型"
                        disabled={index === categories.length - 1}
                        onClick={() => handleMoveCategory(index, 'down')}
                        className="w-7 h-7 rounded-md flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] disabled:opacity-20 disabled:cursor-not-allowed cursor-pointer transition-colors"
                      >
                        <ChevronDownIcon size={13} />
                      </button>

                      {/* Context Menu for Rename & Delete */}
                      <div className="relative">
                        <button
                          type="button"
                          title="更多操作"
                          onClick={(e) => {
                            e.stopPropagation();
                            setOpenCatMenuId(openCatMenuId === cat.id ? null : cat.id);
                          }}
                          className="w-7 h-7 rounded-md flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
                        >
                          <MoreVerticalIcon size={13} />
                        </button>

                        {openCatMenuId === cat.id && (
                          <div
                            onClick={(e) => e.stopPropagation()}
                            className="absolute right-0 top-full mt-1 w-28 bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] rounded-lg shadow-[var(--shadow-flyout)] py-1 z-30 flex flex-col text-xs animate-fade-in"
                          >
                            <button
                              type="button"
                              onClick={() => {
                                setEditingCatId(cat.id);
                                setEditingCatName(cat.name);
                                setOpenCatMenuId(null);
                              }}
                              className="px-3 py-1.5 text-left text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
                            >
                              重命名类型
                            </button>
                            <button
                              type="button"
                              onClick={() => {
                                setOpenCatMenuId(null);
                                onDeleteCategory(cat.id);
                              }}
                              className="px-3 py-1.5 text-left text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] cursor-pointer transition-colors"
                            >
                              删除类型
                            </button>
                          </div>
                        )}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Section 2: Channels & Accounts (Assets & Liabilities Workbench) */}
      {activeTab === 'paymentMethods' && (
        <div className="flex flex-col gap-5">
          {/* Subsection 2.1: Asset Channels */}
          <div className="bg-[var(--color-card-bg)] rounded-2xl border border-[var(--color-neutral-stroke)] p-5.5 shadow-[var(--shadow-card)] flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h4 className="text-base font-semibold text-[var(--color-neutral-fg-1)]">
                  资产渠道
                </h4>
                <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-[var(--color-hover-bg)] border border-[var(--color-neutral-stroke)] text-[var(--color-neutral-fg-3)]">
                  {assetChannels.length}
                </span>
              </div>
              {!showAddAssetInput && (
                <button
                  type="button"
                  onClick={() => setShowAddAssetInput(true)}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--color-hover-bg)] hover:bg-[var(--color-brand-light)] hover:text-[var(--color-brand)] text-xs font-semibold text-[var(--color-neutral-fg-2)] cursor-pointer transition-colors"
                >
                  <PlusIcon size={14} />
                  <span>添加资产渠道</span>
                </button>
              )}
            </div>

            {/* Inline Creation Form (Asset) */}
            {showAddAssetInput && (
              <form
                onSubmit={handleCreateAssetChannel}
                className="flex flex-wrap items-center gap-2 p-3 bg-[var(--color-hover-bg)] rounded-xl border border-[var(--color-neutral-stroke)] animate-fade-in"
              >
                <input
                  type="text"
                  autoFocus
                  value={newAssetName}
                  onChange={(e) => setNewAssetName(e.target.value)}
                  placeholder="渠道名称 (如: 工商银行卡、微信零钱)"
                  className="flex-2 min-w-[150px] px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                />
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={newAssetBalance}
                  onChange={(e) => setNewAssetBalance(e.target.value)}
                  placeholder="初始余额 (元)"
                  className="flex-1 min-w-[110px] px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                />
                <button
                  type="submit"
                  className="px-3.5 py-1.5 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer"
                >
                  保存
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setShowAddAssetInput(false);
                    setNewAssetName('');
                    setNewAssetBalance('');
                  }}
                  className="px-3 py-1.5 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-card-bg)] cursor-pointer"
                >
                  取消
                </button>
              </form>
            )}

            {/* Asset Channel Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2.5">
              {assetChannels.map((pm) => {
                if (editingPmId === pm.id) {
                  return (
                    <form
                      key={pm.id}
                      onSubmit={(e) => handleSavePmEdit(pm, e)}
                      className="col-span-1 p-3 rounded-xl border border-[var(--color-brand)] bg-[var(--color-card-bg)] flex flex-col gap-2 shadow-sm"
                    >
                      <input
                        type="text"
                        autoFocus
                        value={editingPmName}
                        onChange={(e) => setEditingPmName(e.target.value)}
                        placeholder="渠道名称"
                        className="px-2.5 py-1 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                      />
                      <div className="flex items-center gap-1.5">
                        <span className="text-[11px] text-[var(--color-neutral-fg-3)] flex-shrink-0">初始余额:</span>
                        <input
                          type="number"
                          step="0.01"
                          min="0"
                          value={editingPmInitBal}
                          onChange={(e) => setEditingPmInitBal(e.target.value)}
                          placeholder="初始余额"
                          className="w-full px-2 py-1 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                        />
                      </div>
                      <div className="flex items-center gap-1.5 justify-end mt-1">
                        <button
                          type="submit"
                          className="px-3 py-1 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer"
                        >
                          保存
                        </button>
                        <button
                          type="button"
                          onClick={() => setEditingPmId(null)}
                          className="px-2.5 py-1 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)] cursor-pointer"
                        >
                          取消
                        </button>
                      </div>
                    </form>
                  );
                }

                return (
                  <div
                    key={pm.id}
                    className="group bg-[var(--color-subtle-bg)] hover:bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] hover:border-[var(--color-neutral-stroke-strong)] rounded-xl p-3 flex flex-col gap-1.5 transition-all shadow-[var(--shadow-card)]"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2 truncate">
                        <span className="w-2 h-2 rounded-full bg-[var(--color-brand)] flex-shrink-0" />
                        <span className="text-xs font-semibold text-[var(--color-neutral-fg-1)] truncate">
                          {pm.name}
                        </span>
                      </div>
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          type="button"
                          title="编辑渠道"
                          onClick={() => handleStartEditPm(pm)}
                          className="text-[var(--color-neutral-fg-3)] hover:text-[var(--color-brand)] hover:bg-[var(--color-brand-light)] w-6 h-6 rounded flex items-center justify-center cursor-pointer transition-colors"
                        >
                          <EditIcon size={12} />
                        </button>
                        <button
                          type="button"
                          title="删除渠道"
                          onClick={() => onDeletePaymentMethod(pm.id)}
                          className="text-[var(--color-neutral-fg-3)] hover:text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] w-6 h-6 rounded flex items-center justify-center cursor-pointer transition-colors"
                        >
                          <TrashIcon size={13} />
                        </button>
                      </div>
                    </div>
                    <span className="text-[11px] text-[var(--color-neutral-fg-3)] pl-4 tabular-num">
                      初始余额: ¥{pm.initial_balance.toFixed(2)}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>

          {/* Subsection 2.2: Liability Channels */}
          <div className="bg-[var(--color-card-bg)] rounded-2xl border border-[var(--color-neutral-stroke)] p-5.5 shadow-[var(--shadow-card)] flex flex-col gap-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <h4 className="text-base font-semibold text-[var(--color-neutral-fg-1)]">
                  负债渠道
                </h4>
                <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-[var(--color-hover-bg)] border border-[var(--color-neutral-stroke)] text-[var(--color-neutral-fg-3)]">
                  {liabilityChannels.length}
                </span>
              </div>
              {!showAddLiabilityInput && (
                <button
                  type="button"
                  onClick={() => setShowAddLiabilityInput(true)}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--color-hover-bg)] hover:bg-[var(--color-brand-light)] hover:text-[var(--color-brand)] text-xs font-semibold text-[var(--color-neutral-fg-2)] cursor-pointer transition-colors"
                >
                  <PlusIcon size={14} />
                  <span>添加负债渠道</span>
                </button>
              )}
            </div>

            {/* Inline Creation Form (Liability) */}
            {showAddLiabilityInput && (
              <form
                onSubmit={handleCreateLiabilityChannel}
                className="flex flex-wrap items-center gap-2 p-3 bg-[var(--color-hover-bg)] rounded-xl border border-[var(--color-neutral-stroke)] animate-fade-in"
              >
                <input
                  type="text"
                  autoFocus
                  value={newLiabilityName}
                  onChange={(e) => setNewLiabilityName(e.target.value)}
                  placeholder="渠道名称 (如: 招商信用卡、花呗)"
                  className="flex-2 min-w-[150px] px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                />
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={newLiabilityDebt}
                  onChange={(e) => setNewLiabilityDebt(e.target.value)}
                  placeholder="初始欠款 (元)"
                  className="flex-1 min-w-[100px] px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                />
                <input
                  type="number"
                  step="0.01"
                  min="0"
                  value={newLiabilityLimit}
                  onChange={(e) => setNewLiabilityLimit(e.target.value)}
                  placeholder="授信额度 (0为不限)"
                  className="flex-1 min-w-[110px] px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                />
                <button
                  type="submit"
                  className="px-3.5 py-1.5 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer"
                >
                  保存
                </button>
                <button
                  type="button"
                  onClick={() => {
                    setShowAddLiabilityInput(false);
                    setNewLiabilityName('');
                    setNewLiabilityDebt('');
                    setNewLiabilityLimit('');
                  }}
                  className="px-3 py-1.5 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-card-bg)] cursor-pointer"
                >
                  取消
                </button>
              </form>
            )}

            {/* Liability Channel Grid */}
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2.5">
              {liabilityChannels.map((pm) => {
                if (editingPmId === pm.id) {
                  return (
                    <form
                      key={pm.id}
                      onSubmit={(e) => handleSavePmEdit(pm, e)}
                      className="col-span-1 p-3 rounded-xl border border-[var(--color-brand)] bg-[var(--color-card-bg)] flex flex-col gap-2 shadow-sm"
                    >
                      <input
                        type="text"
                        autoFocus
                        value={editingPmName}
                        onChange={(e) => setEditingPmName(e.target.value)}
                        placeholder="渠道名称"
                        className="px-2.5 py-1 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                      />
                      <div className="grid grid-cols-2 gap-2">
                        <div className="flex flex-col gap-0.5">
                          <span className="text-[10px] text-[var(--color-neutral-fg-3)]">初始欠款</span>
                          <input
                            type="number"
                            step="0.01"
                            min="0"
                            value={editingPmInitBal}
                            onChange={(e) => setEditingPmInitBal(e.target.value)}
                            className="px-2 py-1 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                          />
                        </div>
                        <div className="flex flex-col gap-0.5">
                          <span className="text-[10px] text-[var(--color-neutral-fg-3)]">授信额度</span>
                          <input
                            type="number"
                            step="0.01"
                            min="0"
                            value={editingPmLimit}
                            onChange={(e) => setEditingPmLimit(e.target.value)}
                            className="px-2 py-1 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                          />
                        </div>
                      </div>
                      <div className="flex items-center gap-1.5 justify-end mt-1">
                        <button
                          type="submit"
                          className="px-3 py-1 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer"
                        >
                          保存
                        </button>
                        <button
                          type="button"
                          onClick={() => setEditingPmId(null)}
                          className="px-2.5 py-1 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)] cursor-pointer"
                        >
                          取消
                        </button>
                      </div>
                    </form>
                  );
                }

                return (
                  <div
                    key={pm.id}
                    className="group bg-[var(--color-subtle-bg)] hover:bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] hover:border-[var(--color-neutral-stroke-strong)] rounded-xl p-3 flex flex-col gap-1.5 transition-all shadow-[var(--shadow-card)]"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2 truncate">
                        <span className="w-2 h-2 rounded-full bg-[var(--color-expense-dark)] flex-shrink-0" />
                        <span className="text-xs font-semibold text-[var(--color-neutral-fg-1)] truncate">
                          {pm.name}
                        </span>
                      </div>
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button
                          type="button"
                          title="编辑渠道"
                          onClick={() => handleStartEditPm(pm)}
                          className="text-[var(--color-neutral-fg-3)] hover:text-[var(--color-brand)] hover:bg-[var(--color-brand-light)] w-6 h-6 rounded flex items-center justify-center cursor-pointer transition-colors"
                        >
                          <EditIcon size={12} />
                        </button>
                        <button
                          type="button"
                          title="删除渠道"
                          onClick={() => onDeletePaymentMethod(pm.id)}
                          className="text-[var(--color-neutral-fg-3)] hover:text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] w-6 h-6 rounded flex items-center justify-center cursor-pointer transition-colors"
                        >
                          <TrashIcon size={13} />
                        </button>
                      </div>
                    </div>
                    <span className="text-[11px] text-[var(--color-neutral-fg-3)] pl-4 tabular-num">
                      {pm.credit_limit > 0 ? `额度: ¥${pm.credit_limit.toFixed(2)}` : '额度: 不限'} · 初始欠款: ¥{pm.initial_balance.toFixed(2)}
                    </span>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* ========================================================
          Layer 3: Progressive Disclosure Container (Tag Drawer)
          ======================================================== */}
      {activeDrawerCategory && (
        <div
          className="fixed inset-0 z-[1000] bg-black/45 backdrop-blur-sm flex justify-end animate-fade-in"
          onClick={() => {
            setActiveDrawerCategoryId(null);
            setDrawerNewTagName('');
            setEditingTagId(null);
          }}
        >
          <div
            className="w-full max-w-[420px] h-full bg-[var(--color-card-bg)] border-l border-[var(--color-neutral-stroke)] shadow-[var(--shadow-modal)] flex flex-col overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Drawer Header */}
            <div className="px-5 py-4 border-b border-[var(--color-neutral-stroke)] flex items-center justify-between flex-shrink-0 bg-[var(--color-subtle-bg)]">
              <div className="flex items-center gap-2">
                <h4 className="text-sm font-semibold text-[var(--color-neutral-fg-1)]">
                  {activeDrawerCategory.name} · 细分标签
                </h4>
                <span className="text-[11px] font-medium px-2 py-0.5 rounded-full bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] text-[var(--color-neutral-fg-3)]">
                  {activeDrawerCategory.tags?.length || 0}
                </span>
              </div>
              <button
                type="button"
                onClick={() => {
                  setActiveDrawerCategoryId(null);
                  setDrawerNewTagName('');
                  setEditingTagId(null);
                }}
                className="w-7 h-7 rounded-lg flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
              >
                <CloseIcon size={16} />
              </button>
            </div>

            {/* Drawer Body */}
            <div className="p-5 flex flex-col gap-4 overflow-y-auto flex-1">
              {/* Add Tag Input Form inside Drawer */}
              <form
                onSubmit={(e) => handleCreateTagInDrawer(activeDrawerCategory.id, e)}
                className="flex items-center gap-2"
              >
                <input
                  type="text"
                  value={drawerNewTagName}
                  onChange={(e) => setDrawerNewTagName(e.target.value)}
                  placeholder="添加细分标签 (如：午餐、地铁)"
                  className="flex-1 px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)] transition-colors"
                />
                <button
                  type="submit"
                  className="px-3.5 py-1.5 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer flex-shrink-0 hover:bg-[var(--color-brand-hover)] transition-colors"
                >
                  添加
                </button>
              </form>

              {/* Tag List */}
              <div className="flex flex-col gap-2">
                {activeDrawerCategory.tags && activeDrawerCategory.tags.length > 0 ? (
                  activeDrawerCategory.tags.map((tag) => (
                    <div
                      key={tag.id}
                      className="bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke)] rounded-lg p-2.5 px-3 flex items-center justify-between text-xs transition-colors hover:border-[var(--color-neutral-stroke-strong)]"
                    >
                      {editingTagId === tag.id ? (
                        <form
                          onSubmit={(e) => handleSaveTagRename(tag, e, activeDrawerCategory)}
                          className="flex items-center gap-2 w-full animate-fade-in"
                        >
                          <input
                            type="text"
                            autoFocus
                            value={editingTagName}
                            onChange={(e) => setEditingTagName(e.target.value)}
                            className="flex-1 px-2.5 py-1 rounded border border-[var(--color-brand)] bg-[var(--color-card-bg)] text-xs text-[var(--color-neutral-fg-1)] outline-none"
                          />
                          <button
                            type="submit"
                            className="px-2.5 py-1 rounded bg-[var(--color-brand)] text-white text-[11px] font-medium cursor-pointer"
                          >
                            保存
                          </button>
                          <button
                            type="button"
                            onClick={() => setEditingTagId(null)}
                            className="px-2 py-1 text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] text-xs cursor-pointer"
                          >
                            ✕
                          </button>
                        </form>
                      ) : (
                        <>
                          <span className="font-medium text-[var(--color-neutral-fg-1)] truncate">
                            {tag.name}
                          </span>
                          <div className="flex items-center gap-1">
                            <button
                              type="button"
                              title="重命名标签"
                              onClick={() => {
                                setEditingTagId(tag.id);
                                setEditingTagName(tag.name);
                              }}
                              className="w-6 h-6 rounded flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
                            >
                              <EditIcon size={12} />
                            </button>
                            <button
                              type="button"
                              title="删除标签"
                              onClick={() => onDeleteTag(tag.id)}
                              className="w-6 h-6 rounded flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] cursor-pointer transition-colors"
                            >
                              <TrashIcon size={12} />
                            </button>
                          </div>
                        </>
                      )}
                    </div>
                  ))
                ) : (
                  <div className="text-xs text-[var(--color-neutral-fg-subtle)] py-8 text-center">
                    暂无细分标签，可在上方添加
                  </div>
                )}
              </div>
            </div>

            {/* Drawer Footer */}
            <div className="px-5 py-3 border-t border-[var(--color-neutral-stroke)] flex justify-end bg-[var(--color-subtle-bg)] flex-shrink-0">
              <button
                type="button"
                onClick={() => {
                  setActiveDrawerCategoryId(null);
                  setDrawerNewTagName('');
                  setEditingTagId(null);
                }}
                className="px-4 py-1.5 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs font-medium text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-card-bg)] cursor-pointer transition-colors"
              >
                完成
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
