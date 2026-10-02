import { useState, useEffect } from 'react';
import type { FC, FormEvent } from 'react';
import { Category, PaymentMethod, Tag } from '../lib/api';
import { PlusIcon, ChevronUpIcon, ChevronDownIcon, MoreVerticalIcon, TrashIcon } from '../components/Icons';

interface SettingsPageProps {
  categories: Category[];
  paymentMethods: PaymentMethod[];
  onAddPaymentMethod: (name: string) => Promise<void>;
  onDeletePaymentMethod: (id: number) => Promise<void>;
  onAddCategory: (name: string) => Promise<void>;
  onUpdateCategory: (id: number, name: string, sort_order: number) => Promise<void>;
  onDeleteCategory: (id: number) => Promise<void>;
  onAddTag: (categoryId: number, name: string) => Promise<void>;
  onUpdateTag: (id: number, name: string, sort_order: number) => Promise<void>;
  onDeleteTag: (id: number) => Promise<void>;
}

export const SettingsPage: FC<SettingsPageProps> = ({
  categories,
  paymentMethods,
  onAddPaymentMethod,
  onDeletePaymentMethod,
  onAddCategory,
  onUpdateCategory,
  onDeleteCategory,
  onAddTag,
  onUpdateTag,
  onDeleteTag,
}) => {
  const [newPmName, setNewPmName] = useState('');
  const [showAddPmInput, setShowAddPmInput] = useState(false);

  const [newCatName, setNewCatName] = useState('');
  const [showAddCatInput, setShowAddCatInput] = useState(false);

  const [activeTagInputCatId, setActiveTagInputCatId] = useState<number | null>(null);
  const [newTagName, setNewTagName] = useState('');

  // Dropdown menus state
  const [openCatMenuId, setOpenCatMenuId] = useState<number | null>(null);
  const [openTagMenuId, setOpenTagMenuId] = useState<number | null>(null);

  // Inline rename state
  const [editingCatId, setEditingCatId] = useState<number | null>(null);
  const [editingCatName, setEditingCatName] = useState('');

  const [editingTagId, setEditingTagId] = useState<number | null>(null);
  const [editingTagName, setEditingTagName] = useState('');

  // Close menus on outside click
  useEffect(() => {
    const handleDocumentClick = () => {
      setOpenCatMenuId(null);
      setOpenTagMenuId(null);
    };
    document.addEventListener('click', handleDocumentClick);
    return () => document.removeEventListener('click', handleDocumentClick);
  }, []);

  const handleCreatePaymentMethod = async (e: FormEvent) => {
    e.preventDefault();
    if (!newPmName.trim()) return;
    await onAddPaymentMethod(newPmName.trim());
    setNewPmName('');
    setShowAddPmInput(false);
  };

  const handleCreateCategory = async (e: FormEvent) => {
    e.preventDefault();
    if (!newCatName.trim()) return;
    await onAddCategory(newCatName.trim());
    setNewCatName('');
    setShowAddCatInput(false);
  };

  const handleCreateTag = async (categoryId: number, e: FormEvent) => {
    e.preventDefault();
    if (!newTagName.trim()) return;
    await onAddTag(categoryId, newTagName.trim());
    setNewTagName('');
    setActiveTagInputCatId(null);
  };

  const handleMoveCategory = async (index: number, direction: 'up' | 'down') => {
    const targetIndex = direction === 'up' ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= categories.length) return;

    const itemA = categories[index];
    const itemB = categories[targetIndex];

    const orderForA = targetIndex + 1;
    const orderForB = index + 1;

    try {
      await Promise.all([
        onUpdateCategory(itemA.id, itemA.name, orderForA),
        onUpdateCategory(itemB.id, itemB.name, orderForB),
      ]);
    } catch {
      // Toast and refresh handled in App.tsx
    }
  };

  const handleSaveCatRename = async (cat: Category, e: FormEvent) => {
    e.preventDefault();
    if (!editingCatName.trim() || editingCatName.trim() === cat.name) {
      setEditingCatId(null);
      return;
    }
    await onUpdateCategory(cat.id, editingCatName.trim(), cat.sort_order);
    setEditingCatId(null);
  };

  const handleSaveTagRename = async (tag: Tag, e: FormEvent) => {
    e.preventDefault();
    if (!editingTagName.trim() || editingTagName.trim() === tag.name) {
      setEditingTagId(null);
      return;
    }
    await onUpdateTag(tag.id, editingTagName.trim(), tag.sort_order);
    setEditingTagId(null);
  };

  return (
    <div className="w-full max-w-[900px] flex flex-col gap-6 animate-fade-in pb-16">
      {/* Module 1: Payment Methods */}
      <div className="bg-[var(--color-card-bg)] rounded-2xl border border-[var(--color-neutral-stroke)] p-5.5 shadow-[var(--shadow-card)]">
        <div className="flex items-center justify-between mb-3.5">
          <div>
            <h4 className="text-base font-semibold text-[var(--color-neutral-fg-1)]">支付途径管理</h4>
            <p className="text-xs text-[var(--color-neutral-fg-3)] mt-0.5">
              配置记账时的付款与收款渠道
            </p>
          </div>
          {!showAddPmInput && (
            <button
              type="button"
              onClick={() => setShowAddPmInput(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--color-hover-bg)] hover:bg-[var(--color-brand-light)] hover:text-[var(--color-brand)] text-xs font-semibold text-[var(--color-neutral-fg-2)] cursor-pointer transition-colors"
            >
              <PlusIcon size={14} />
              <span>添加途径</span>
            </button>
          )}
        </div>

        {showAddPmInput && (
          <form onSubmit={handleCreatePaymentMethod} className="flex items-center gap-2 mb-3.5 animate-fade-in">
            <input
              type="text"
              autoFocus
              value={newPmName}
              onChange={(e) => setNewPmName(e.target.value)}
              placeholder="途径名称 (如：交通卡、美团月付)"
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
                setShowAddPmInput(false);
                setNewPmName('');
              }}
              className="px-3 py-1.5 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)] cursor-pointer"
            >
              取消
            </button>
          </form>
        )}

        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
          {paymentMethods.map((pm) => (
            <div
              key={pm.id}
              className="group bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] rounded-xl p-3 flex items-center justify-between hover:border-[var(--color-neutral-stroke-strong)] transition-all"
            >
              <div className="flex items-center gap-2">
                <span className="w-2 h-2 rounded-full bg-[var(--color-brand)]" />
                <span className="text-xs font-medium text-[var(--color-neutral-fg-1)] truncate">
                  {pm.name}
                </span>
              </div>
              <button
                type="button"
                title="删除途径"
                onClick={() => onDeletePaymentMethod(pm.id)}
                className="opacity-0 group-hover:opacity-100 text-[var(--color-neutral-fg-3)] hover:text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] w-6 h-6 rounded flex items-center justify-center cursor-pointer transition-all"
              >
                <TrashIcon size={13} />
              </button>
            </div>
          ))}
        </div>
      </div>

      {/* Module 2: Consumption Categories & Sub-tags */}
      <div className="bg-[var(--color-card-bg)] rounded-2xl border border-[var(--color-neutral-stroke)] p-5.5 shadow-[var(--shadow-card)]">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h4 className="text-base font-semibold text-[var(--color-neutral-fg-1)]">
              消费类型与细分标签
            </h4>
            <p className="text-xs text-[var(--color-neutral-fg-3)] mt-0.5">
              二级级联收纳体系，每个分类可包含专属的二级细分标签
            </p>
          </div>
          {!showAddCatInput && (
            <button
              type="button"
              onClick={() => setShowAddCatInput(true)}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-[var(--color-hover-bg)] hover:bg-[var(--color-brand-light)] hover:text-[var(--color-brand)] text-xs font-semibold text-[var(--color-neutral-fg-2)] cursor-pointer transition-colors"
            >
              <PlusIcon size={14} />
              <span>新增消费类型</span>
            </button>
          )}
        </div>

        {showAddCatInput && (
          <form onSubmit={handleCreateCategory} className="flex items-center gap-2 mb-4 p-3 bg-[var(--color-hover-bg)] rounded-xl border border-[var(--color-neutral-stroke)] animate-fade-in">
            <input
              type="text"
              autoFocus
              value={newCatName}
              onChange={(e) => setNewCatName(e.target.value)}
              placeholder="输入类型名称 (如：宠物养护、学习深造)"
              className="flex-1 px-3 py-1.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
            />
            <button
              type="submit"
              className="px-3.5 py-1.5 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer"
            >
              保存类型
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

        <div className="flex flex-col gap-3">
          {categories.map((cat, index) => (
            <div
              key={cat.id}
              className="group/card border border-[var(--color-neutral-stroke)] rounded-xl p-3.5 bg-[var(--color-card-bg)]"
            >
              {/* Category Header Row */}
              <div className="flex items-center justify-between mb-2.5">
                <div className="flex items-center gap-2">
                  <span className="text-sm font-semibold text-[var(--color-neutral-fg-1)]">
                    {cat.name}
                  </span>
                  <span className="text-[11px] text-[var(--color-neutral-fg-subtle)]">
                    ({cat.tags?.length || 0} 个细分标签)
                  </span>
                </div>

                <div className="flex items-center gap-1">
                  {/* Move Up */}
                  <button
                    type="button"
                    title="上移类型"
                    disabled={index === 0}
                    onClick={() => handleMoveCategory(index, 'up')}
                    className="w-6 h-6 rounded flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] disabled:opacity-20 disabled:cursor-not-allowed cursor-pointer transition-colors"
                  >
                    <ChevronUpIcon size={13} />
                  </button>
                  {/* Move Down */}
                  <button
                    type="button"
                    title="下移类型"
                    disabled={index === categories.length - 1}
                    onClick={() => handleMoveCategory(index, 'down')}
                    className="w-6 h-6 rounded flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] disabled:opacity-20 disabled:cursor-not-allowed cursor-pointer transition-colors"
                  >
                    <ChevronDownIcon size={13} />
                  </button>

                  {/* Secondary Context Menu */}
                  <div className="relative">
                    <button
                      type="button"
                      title="更多操作"
                      onClick={(e) => {
                        e.stopPropagation();
                        setOpenTagMenuId(null);
                        setOpenCatMenuId(openCatMenuId === cat.id ? null : cat.id);
                      }}
                      className="w-6 h-6 rounded flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
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

              {/* Inline Category Rename Form */}
              {editingCatId === cat.id && (
                <form
                  onSubmit={(e) => handleSaveCatRename(cat, e)}
                  className="flex items-center gap-2 mb-3 p-2.5 bg-[var(--color-hover-bg)] rounded-xl border border-[var(--color-neutral-stroke)] animate-fade-in"
                >
                  <input
                    type="text"
                    autoFocus
                    value={editingCatName}
                    onChange={(e) => setEditingCatName(e.target.value)}
                    className="flex-1 px-3 py-1 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)]"
                  />
                  <button
                    type="submit"
                    className="px-3 py-1 rounded-lg bg-[var(--color-brand)] text-white text-xs font-medium cursor-pointer"
                  >
                    保存
                  </button>
                  <button
                    type="button"
                    onClick={() => setEditingCatId(null)}
                    className="px-2.5 py-1 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-card-bg)] cursor-pointer"
                  >
                    取消
                  </button>
                </form>
              )}

              {/* Sub-tags Chip Container */}
              <div className="flex flex-wrap gap-2 items-center">
                {cat.tags?.map((tag) => {
                  if (editingTagId === tag.id) {
                    return (
                      <form
                        key={tag.id}
                        onSubmit={(e) => handleSaveTagRename(tag, e)}
                        className="inline-flex items-center gap-1"
                      >
                        <input
                          type="text"
                          autoFocus
                          value={editingTagName}
                          onChange={(e) => setEditingTagName(e.target.value)}
                          className="w-24 px-2 py-0.5 rounded border border-[var(--color-brand)] bg-[var(--color-card-bg)] text-xs text-[var(--color-neutral-fg-1)] outline-none"
                        />
                        <button
                          type="submit"
                          className="px-2 py-0.5 rounded bg-[var(--color-brand)] text-white text-[11px] cursor-pointer"
                        >
                          保存
                        </button>
                        <button
                          type="button"
                          onClick={() => setEditingTagId(null)}
                          className="px-1.5 py-0.5 text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] text-xs cursor-pointer"
                        >
                          ✕
                        </button>
                      </form>
                    );
                  }

                  return (
                    <div
                      key={tag.id}
                      className="relative group/chip bg-[var(--color-hover-bg)] border border-[var(--color-neutral-stroke)] rounded-md px-2.5 py-1 text-xs text-[var(--color-neutral-fg-2)] flex items-center gap-1.5 transition-colors hover:bg-[var(--color-canvas-bg)]"
                    >
                      <span>{tag.name}</span>
                      <button
                        type="button"
                        title="更多操作"
                        onClick={(e) => {
                          e.stopPropagation();
                          setOpenCatMenuId(null);
                          setOpenTagMenuId(openTagMenuId === tag.id ? null : tag.id);
                        }}
                        className="text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] cursor-pointer text-[11px] font-bold px-0.5 rounded hover:bg-[var(--color-hover-bg)]"
                      >
                        ···
                      </button>

                      {openTagMenuId === tag.id && (
                        <div
                          onClick={(e) => e.stopPropagation()}
                          className="absolute left-0 top-full mt-1 w-28 bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] rounded-lg shadow-[var(--shadow-flyout)] py-1 z-30 flex flex-col text-xs animate-fade-in"
                        >
                          <button
                            type="button"
                            onClick={() => {
                              setEditingTagId(tag.id);
                              setEditingTagName(tag.name);
                              setOpenTagMenuId(null);
                            }}
                            className="px-3 py-1.5 text-left text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
                          >
                            重命名标签
                          </button>
                          <button
                            type="button"
                            onClick={() => {
                              setOpenTagMenuId(null);
                              onDeleteTag(tag.id);
                            }}
                            className="px-3 py-1.5 text-left text-[var(--color-expense-dark)] hover:bg-[var(--color-expense-bg)] cursor-pointer transition-colors"
                          >
                            删除标签
                          </button>
                        </div>
                      )}
                    </div>
                  );
                })}

                {/* Inline add tag input or button */}
                {activeTagInputCatId === cat.id ? (
                  <form
                    onSubmit={(e) => handleCreateTag(cat.id, e)}
                    className="inline-flex items-center gap-1"
                  >
                    <input
                      type="text"
                      autoFocus
                      value={newTagName}
                      onChange={(e) => setNewTagName(e.target.value)}
                      placeholder="标签名"
                      className="w-24 px-2 py-0.5 rounded border border-[var(--color-brand)] bg-[var(--color-card-bg)] text-xs text-[var(--color-neutral-fg-1)] outline-none"
                    />
                    <button
                      type="submit"
                      className="px-2 py-0.5 rounded bg-[var(--color-brand)] text-white text-[11px] cursor-pointer"
                    >
                      添加
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setActiveTagInputCatId(null);
                        setNewTagName('');
                      }}
                      className="px-1.5 py-0.5 text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] text-xs cursor-pointer"
                    >
                      ✕
                    </button>
                  </form>
                ) : (
                  <button
                    type="button"
                    onClick={() => {
                      setActiveTagInputCatId(cat.id);
                      setNewTagName('');
                    }}
                    className="border border-dashed border-[var(--color-neutral-stroke-strong)] hover:border-[var(--color-brand)] hover:bg-[var(--color-brand-light)] text-[var(--color-brand)] rounded-md px-2.5 py-1 text-xs cursor-pointer transition-colors"
                  >
                    + 新增标签
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
