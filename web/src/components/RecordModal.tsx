import { useState, useEffect, useRef } from 'react';
import type { FC, FormEvent } from 'react';
import { CloseIcon, ChevronDownIcon, LockIcon } from './Icons';
import { Category, PaymentMethod, Transaction } from '../lib/api';

interface RecordModalProps {
  isOpen: boolean;
  onClose: () => void;
  categories: Category[];
  paymentMethods: PaymentMethod[];
  initialTransaction?: Transaction | null;
  onNavigateToSettings?: () => void;
  onSubmit: (data: {
    type?: 'expense' | 'income' | 'repayment';
    amount: number;
    description: string;
    payment_method_id: number;
    source_payment_method_id?: number;
    category_id: number;
    tag_id: number;
    transacted_at: string;
  }) => Promise<void>;
}

export const RecordModal: FC<RecordModalProps> = ({
  isOpen,
  onClose,
  onNavigateToSettings,
  categories,
  paymentMethods,
  initialTransaction,
  onSubmit,
}) => {
  const [recordType, setRecordType] = useState<'expense' | 'income' | 'repayment'>('expense');
  const [amountStr, setAmountStr] = useState('');
  const [description, setDescription] = useState('');
  const [paymentMethodId, setPaymentMethodId] = useState<number>(0);
  const [sourcePaymentMethodId, setSourcePaymentMethodId] = useState<number | undefined>(undefined);
  const [categoryId, setCategoryId] = useState<number>(0);
  const [tagId, setTagId] = useState<number>(0);
  const [transactedAt, setTransactedAt] = useState('');

  // Cascading Flyout state
  const [flyoutOpen, setFlyoutOpen] = useState(false);
  const [hoverCategoryId, setHoverCategoryId] = useState<number>(0);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const flyoutRef = useRef<HTMLDivElement>(null);
  const amountInputRef = useRef<HTMLInputElement>(null);

  const assetMethods = paymentMethods.filter((pm) => pm.type === 'asset');
  const liabilityMethods = paymentMethods.filter((pm) => pm.type === 'liability');

  // Initialize or reset when modal opens or initialTransaction changes
  useEffect(() => {
    if (!isOpen) {
      setFlyoutOpen(false);
      setError(null);
      return;
    }

    if (initialTransaction) {
      const initialType = initialTransaction.type || (initialTransaction.amount_cents < 0 ? 'expense' : 'income');
      setRecordType(initialType);
      setAmountStr(String(Math.abs(initialTransaction.amount)));
      setDescription(initialTransaction.description);
      setPaymentMethodId(initialTransaction.payment_method_id);
      setSourcePaymentMethodId(initialTransaction.source_payment_method_id);
      setCategoryId(initialTransaction.category_id);
      setTagId(initialTransaction.tag_id);
      setHoverCategoryId(initialTransaction.category_id);
      // Format transacted_at for datetime-local input: YYYY-MM-DDTHH:mm
      try {
        const d = new Date(initialTransaction.transacted_at);
        const pad = (n: number) => String(n).padStart(2, '0');
        const localDT = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
        setTransactedAt(localDT);
      } catch {
        setTransactedAt('');
      }
    } else {
      setRecordType('expense');
      setAmountStr('');
      setDescription('');
      setError(null);
      setSourcePaymentMethodId(undefined);

      // Default payment method
      if (paymentMethods.length > 0) {
        setPaymentMethodId(paymentMethods[0].id);
      }

      // Default category and tag (prefer non-repayment default category)
      const defaultCat = categories.find((c) => c.name !== '债务偿还') || categories[0];
      if (defaultCat) {
        setCategoryId(defaultCat.id);
        setHoverCategoryId(defaultCat.id);
        if (defaultCat.tags && defaultCat.tags.length > 0) {
          setTagId(defaultCat.tags[0].id);
        } else {
          setTagId(0);
        }
      }

      // Default to current local time
      const now = new Date();
      const pad = (n: number) => String(n).padStart(2, '0');
      const localDT = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}T${pad(now.getHours())}:${pad(now.getMinutes())}`;
      setTransactedAt(localDT);
    }

    setTimeout(() => {
      amountInputRef.current?.focus();
    }, 50);
  }, [isOpen, initialTransaction, categories, paymentMethods]);

  // Handle outside click to close flyout
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (flyoutRef.current && !flyoutRef.current.contains(event.target as Node)) {
        setFlyoutOpen(false);
      }
    }
    if (flyoutOpen) {
      document.addEventListener('mousedown', handleClickOutside);
    }
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
    };
  }, [flyoutOpen]);

  // Keyboard shortcut: ESC to close
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (!isOpen) return;
      if (e.key === 'Escape') {
        if (flyoutOpen) {
          setFlyoutOpen(false);
        } else {
          onClose();
        }
      }
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, flyoutOpen, onClose]);

  if (!isOpen) return null;

  const currentCategory = categories.find((c) => c.id === categoryId);
  const currentTag = currentCategory?.tags?.find((t) => t.id === tagId);

  const hoverCategory = categories.find((c) => c.id === hoverCategoryId) || currentCategory;

  const handleSwitchType = (newType: 'expense' | 'income' | 'repayment') => {
    if (initialTransaction) return;
    setRecordType(newType);

    if (newType === 'repayment') {
      if (liabilityMethods.length > 0 && !liabilityMethods.some((pm) => pm.id === paymentMethodId)) {
        setPaymentMethodId(liabilityMethods[0].id);
      }
      if (assetMethods.length > 0) {
        setSourcePaymentMethodId(assetMethods[0].id);
      } else {
        setSourcePaymentMethodId(undefined);
      }
      const repCat = categories.find((c) => c.name === '债务偿还');
      if (repCat) {
        setCategoryId(repCat.id);
        setHoverCategoryId(repCat.id);
        if (repCat.tags && repCat.tags.length > 0) {
          setTagId(repCat.tags[0].id);
        }
      }
    } else if (newType === 'income') {
      if (assetMethods.length > 0 && !assetMethods.some((pm) => pm.id === paymentMethodId)) {
        setPaymentMethodId(assetMethods[0].id);
      }
      const normalCat = categories.find((c) => c.name !== '债务偿还') || categories[0];
      if (categoryId && categories.find((c) => c.id === categoryId)?.name === '债务偿还' && normalCat) {
        setCategoryId(normalCat.id);
        setHoverCategoryId(normalCat.id);
        setTagId(normalCat.tags?.[0]?.id || 0);
      }
      setSourcePaymentMethodId(undefined);
    } else {
      const normalCat = categories.find((c) => c.name !== '债务偿还') || categories[0];
      if (categoryId && categories.find((c) => c.id === categoryId)?.name === '债务偿还' && normalCat) {
        setCategoryId(normalCat.id);
        setHoverCategoryId(normalCat.id);
        setTagId(normalCat.tags?.[0]?.id || 0);
      }
      setSourcePaymentMethodId(undefined);
    }
  };

  const handleAmountChange = (val: string) => {
    if (!initialTransaction) {
      if (val.startsWith('+')) {
        handleSwitchType('income');
        val = val.substring(1);
      } else if (val.startsWith('-')) {
        handleSwitchType('expense');
        val = val.substring(1);
      }
    }
    // Only allow numbers and decimal point
    if (/^\d*\.?\d*$/.test(val)) {
      setAmountStr(val);
    }
  };

  const handleFormSubmit = async (e: FormEvent) => {
    e.preventDefault();
    const parsedAmount = parseFloat(amountStr);
    if (isNaN(parsedAmount) || parsedAmount <= 0) {
      setError('请输入有效金额');
      return;
    }
    if (!description.trim()) {
      setError('请输入用途说明');
      return;
    }
    if (!paymentMethodId) {
      setError(recordType === 'repayment' ? '请选择还入负债账户' : '请选择支付途径');
      return;
    }

    let finalCatId = categoryId;
    let finalTagId = tagId;
    if (recordType === 'repayment') {
      const repCat = categories.find((c) => c.name === '债务偿还');
      if (repCat) {
        finalCatId = repCat.id;
        finalTagId = repCat.tags?.[0]?.id || tagId;
      }
    }

    if (!finalCatId || !finalTagId) {
      setError('请选择消费类型与细分标签');
      return;
    }

    const finalAmount = recordType === 'expense' ? -parsedAmount : parsedAmount;
    let finalTransactedAt: string | undefined = undefined;
    if (transactedAt) {
      const d = new Date(transactedAt);
      if (!isNaN(d.getTime())) {
        finalTransactedAt = d.toISOString();
      }
    }

    setSubmitting(true);
    setError(null);

    try {
      await onSubmit({
        type: recordType,
        amount: finalAmount,
        description: description.trim(),
        payment_method_id: paymentMethodId,
        source_payment_method_id: recordType === 'repayment' ? sourcePaymentMethodId : undefined,
        category_id: finalCatId,
        tag_id: finalTagId,
        transacted_at: finalTransactedAt || new Date().toISOString(),
      });
      onClose();
    } catch (err: any) {
      setError(err?.message || '保存失败');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-[1000] bg-black/45 backdrop-blur-sm flex items-center justify-center p-3 sm:p-4">
      <div className="w-full max-w-[520px] max-h-[90vh] bg-[var(--color-card-bg)] rounded-2xl shadow-[var(--shadow-modal)] border border-[var(--color-neutral-stroke)] flex flex-col overflow-hidden animate-fade-in relative">
        {/* Header */}
        <div className="px-5 sm:px-6 py-4 border-b border-[var(--color-neutral-stroke)] flex items-center justify-between flex-shrink-0">
          <h3 className="text-base font-semibold text-[var(--color-neutral-fg-1)]">
            {initialTransaction ? '编辑账单' : '记账'}
          </h3>
          <button
            type="button"
            onClick={onClose}
            className="w-7 h-7 rounded-lg flex items-center justify-center text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
          >
            <CloseIcon size={16} />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleFormSubmit} className="p-5 sm:p-6 flex flex-col gap-4 overflow-y-auto flex-1">
          {/* Top Segmented Capsule Slider for Expense / Income / Repayment */}
          <div
            className={`relative bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke)] rounded-xl p-1 grid grid-cols-3 select-none ${
              initialTransaction ? 'opacity-85' : ''
            }`}
          >
            {/* Smooth sliding indicator */}
            <div
              className={`absolute top-1 bottom-1 left-1 w-[calc((100%-8px)/3)] rounded-lg transition-transform duration-200 ease-out shadow-sm ${
                recordType === 'expense'
                  ? 'translate-x-0 bg-[var(--color-expense-bg)] border border-[var(--color-expense-stroke)]'
                  : recordType === 'income'
                  ? 'translate-x-full bg-[var(--color-income-bg)] border border-[var(--color-income-stroke)]'
                  : 'translate-x-[200%] bg-[rgba(0,120,212,0.12)] border border-[rgba(0,120,212,0.35)]'
              }`}
            />
            <button
              type="button"
              disabled={!!initialTransaction}
              onClick={() => handleSwitchType('expense')}
              className={`relative z-10 py-2 text-center text-xs font-semibold transition-colors duration-150 ${
                initialTransaction ? 'cursor-not-allowed' : 'cursor-pointer'
              } ${
                recordType === 'expense'
                  ? 'text-[var(--color-expense-dark)]'
                  : 'text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)]'
              }`}
            >
              − 支出
            </button>
            <button
              type="button"
              disabled={!!initialTransaction}
              onClick={() => handleSwitchType('income')}
              className={`relative z-10 py-2 text-center text-xs font-semibold transition-colors duration-150 ${
                initialTransaction ? 'cursor-not-allowed' : 'cursor-pointer'
              } ${
                recordType === 'income'
                  ? 'text-[var(--color-income-dark)]'
                  : 'text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)]'
              }`}
            >
              + 收入
            </button>
            <button
              type="button"
              disabled={!!initialTransaction}
              onClick={() => handleSwitchType('repayment')}
              className={`relative z-10 py-2 text-center text-xs font-semibold transition-colors duration-150 ${
                initialTransaction ? 'cursor-not-allowed' : 'cursor-pointer'
              } ${
                recordType === 'repayment'
                  ? 'text-[var(--color-brand)]'
                  : 'text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)]'
              }`}
            >
              ↺ 还款
            </button>
          </div>

          {/* Hero Amount Box */}
          <div className="bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke)] rounded-xl p-3.5 focus-within:border-[var(--color-brand)] focus-within:bg-[var(--color-card-bg)] transition-colors">
            <div className="mb-1.5">
              <span className="text-xs text-[var(--color-neutral-fg-3)]">账单金额</span>
            </div>

            <div className="flex items-baseline gap-2">
              <span className="text-2xl font-semibold text-[var(--color-neutral-fg-2)]">¥</span>
              <input
                ref={amountInputRef}
                type="text"
                inputMode="decimal"
                value={amountStr}
                onChange={(e) => handleAmountChange(e.target.value)}
                placeholder="0.00"
                className="w-full bg-transparent border-none outline-none text-3xl font-bold text-[var(--color-neutral-fg-1)] tabular-num placeholder-[var(--color-neutral-fg-subtle)]"
              />
            </div>
          </div>

          {/* Description */}
          <div className="flex flex-col gap-1.5">
            <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">用途说明</label>
            <input
              type="text"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder={recordType === 'repayment' ? '如：归还招行信用卡本月账单' : '如：午餐商务简餐、地铁交通等'}
              className="w-full px-3.5 py-2 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-sm text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)] transition-colors"
            />
          </div>

          {/* Cascading Picker for Category & Tag OR Locked Card for Repayment */}
          {recordType === 'repayment' ? (
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">
                分类与细分标签
              </label>
              <div className="w-full px-3.5 py-2.5 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke)] flex items-center justify-between text-xs select-none">
                <div className="flex items-center gap-2">
                  <span className="font-semibold text-[var(--color-neutral-fg-1)]">
                    {currentCategory?.name || '债务偿还'}
                  </span>
                  <span className="text-xs text-[var(--color-neutral-fg-subtle)]">·</span>
                  <span className="text-[var(--color-brand)] font-medium">
                    {currentTag?.name || '负债还款'}
                  </span>
                </div>
                <div className="flex items-center gap-1 text-[11px] text-[var(--color-neutral-fg-3)]">
                  <LockIcon size={13} className="text-[var(--color-neutral-fg-3)]" />
                  <span>系统固定</span>
                </div>
              </div>
            </div>
          ) : (
            <div className="flex flex-col gap-1.5 relative" ref={flyoutRef}>
              <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">
                分类与细分标签
              </label>
              <button
                type="button"
                onClick={() => {
                  setFlyoutOpen(!flyoutOpen);
                  if (categoryId) setHoverCategoryId(categoryId);
                }}
                className="w-full px-3.5 py-2 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] hover:border-[var(--color-brand)] flex items-center justify-between cursor-pointer transition-colors text-left"
              >
                <div className="flex items-center gap-2 text-sm">
                  <span className="font-semibold text-[var(--color-neutral-fg-1)]">
                    {currentCategory?.name || '未选择分类'}
                  </span>
                  <span className="text-xs text-[var(--color-neutral-fg-subtle)]">›</span>
                  <span className="text-[var(--color-brand)] font-medium">
                    {currentTag?.name || '未选择标签'}
                  </span>
                </div>
                <ChevronDownIcon size={14} className="text-[var(--color-neutral-fg-3)]" />
              </button>

              {/* Cascading Flyout Menu Panel */}
              {flyoutOpen && (
                <div className="absolute top-[calc(100%+4px)] left-0 w-full h-[220px] bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] rounded-xl shadow-[var(--shadow-flyout)] z-50 flex overflow-hidden animate-fade-in">
                  {/* Left Column: Categories */}
                  <div className="w-[44%] border-r border-[var(--color-neutral-stroke)] bg-[var(--color-subtle-bg)] overflow-y-auto p-1.5 flex flex-col gap-0.5">
                    {categories
                      .filter((cat) => cat.name !== '债务偿还')
                      .map((cat) => {
                        const isHovered = cat.id === hoverCategoryId;
                        return (
                          <div
                            key={cat.id}
                            onMouseEnter={() => setHoverCategoryId(cat.id)}
                            onClick={() => setHoverCategoryId(cat.id)}
                            className={`flex items-center justify-between px-2.5 py-2 rounded-md text-xs cursor-pointer transition-colors ${
                              isHovered
                                ? 'bg-[var(--color-card-bg)] text-[var(--color-brand)] font-semibold shadow-sm'
                                : 'text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)]'
                            }`}
                          >
                            <span className="truncate">{cat.name}</span>
                            <span className="text-[10px] text-[var(--color-neutral-fg-subtle)] flex-shrink-0 ml-1">
                              {cat.tags?.length || 0}
                            </span>
                          </div>
                        );
                      })}
                  </div>

                  {/* Right Column: Sub-tags */}
                  <div className="flex-1 overflow-y-auto p-2.5 flex flex-col gap-1 bg-[var(--color-card-bg)]">
                    <div className="text-[11px] text-[var(--color-neutral-fg-3)] font-medium px-1 mb-1">
                      {hoverCategory ? `${hoverCategory.name} 的细分标签` : '标签列表'}
                    </div>

                    {hoverCategory && hoverCategory.tags && hoverCategory.tags.length > 0 ? (
                      hoverCategory.tags.map((tg) => {
                        const isSelected = categoryId === hoverCategory.id && tagId === tg.id;
                        return (
                          <button
                            key={tg.id}
                            type="button"
                            onClick={() => {
                              setCategoryId(hoverCategory.id);
                              setTagId(tg.id);
                              setFlyoutOpen(false);
                            }}
                            className={`flex items-center justify-between px-2.5 py-1.5 rounded-md text-xs cursor-pointer transition-colors text-left ${
                              isSelected
                                ? 'bg-[var(--color-brand-light)] text-[var(--color-brand)] font-semibold border border-[var(--color-brand-stroke)]'
                                : 'text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)] hover:text-[var(--color-neutral-fg-1)]'
                            }`}
                          >
                            <span>{tg.name}</span>
                            {isSelected && <span className="text-[11px]">✓</span>}
                          </button>
                        );
                      })
                    ) : (
                      <div className="text-xs text-[var(--color-neutral-fg-subtle)] p-2">
                        暂无细分标签
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* Payment Method Selector(s) */}
          {recordType === 'repayment' ? (
            <>
              {/* Target Liability Channel */}
              <div className="flex flex-col gap-1.5">
                <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">
                  还入负债账户
                </label>
                {liabilityMethods.length === 0 ? (
                  <div className="px-3.5 py-2.5 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke)] text-xs text-[var(--color-expense-dark)] flex items-center justify-between">
                    <span>暂无负债渠道，无法记录还款</span>
                    {onNavigateToSettings && (
                      <button
                        type="button"
                        onClick={onNavigateToSettings}
                        className="text-xs font-semibold text-[var(--color-brand)] hover:underline cursor-pointer ml-2 flex-shrink-0"
                      >
                        前往设置添加 →
                      </button>
                    )}
                  </div>
                ) : (
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    {liabilityMethods.map((pm) => {
                      const isSelected = pm.id === paymentMethodId;
                      return (
                        <button
                          key={pm.id}
                          type="button"
                          onClick={() => setPaymentMethodId(pm.id)}
                          className={`py-2 px-1 rounded-lg text-xs font-medium border text-center cursor-pointer transition-all ${
                            isSelected
                              ? 'border-[var(--color-brand)] bg-[var(--color-brand-light)] text-[var(--color-brand)] font-semibold'
                              : 'border-[var(--color-neutral-stroke-strong)] bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)]'
                          }`}
                        >
                          {pm.name}
                        </button>
                      );
                    })}
                  </div>
                )}
              </div>

              {/* Source Asset Channel */}
              <div className="flex flex-col gap-1.5">
                <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">
                  转出资产账户
                </label>
                <div className="grid grid-cols-2 sm:grid-cols-3 gap-2">
                  {assetMethods.map((pm) => {
                    const isSelected = pm.id === sourcePaymentMethodId;
                    return (
                      <button
                        key={pm.id}
                        type="button"
                        onClick={() => setSourcePaymentMethodId(pm.id)}
                        className={`py-2 px-1 rounded-lg text-xs font-medium border text-center cursor-pointer transition-all ${
                          isSelected
                            ? 'border-[var(--color-brand)] bg-[var(--color-brand-light)] text-[var(--color-brand)] font-semibold'
                            : 'border-[var(--color-neutral-stroke-strong)] bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)]'
                        }`}
                      >
                        {pm.name}
                      </button>
                    );
                  })}
                  <button
                    type="button"
                    onClick={() => setSourcePaymentMethodId(undefined)}
                    className={`py-2 px-1 rounded-lg text-xs font-medium border text-center cursor-pointer transition-all ${
                      sourcePaymentMethodId === undefined
                        ? 'border-[var(--color-brand)] bg-[var(--color-brand-light)] text-[var(--color-brand)] font-semibold'
                        : 'border-[var(--color-neutral-stroke-strong)] bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-3)] hover:bg-[var(--color-hover-bg)]'
                    }`}
                  >
                    外部/未记录资金
                  </button>
                </div>
              </div>
            </>
          ) : (
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">
                {recordType === 'income' ? '存入渠道' : '支付途径'}
              </label>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                {(recordType === 'income' ? assetMethods : paymentMethods).map((pm) => {
                  const isSelected = pm.id === paymentMethodId;
                  return (
                    <button
                      key={pm.id}
                      type="button"
                      onClick={() => setPaymentMethodId(pm.id)}
                      className={`py-2 px-1 rounded-lg text-xs font-medium border text-center cursor-pointer transition-all ${
                        isSelected
                          ? 'border-[var(--color-brand)] bg-[var(--color-brand-light)] text-[var(--color-brand)] font-semibold'
                          : 'border-[var(--color-neutral-stroke-strong)] bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)]'
                      }`}
                    >
                      {pm.name}
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {/* Date & Time */}
          <div className="flex flex-col gap-1.5">
            <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">记账时间</label>
            <input
              type="datetime-local"
              value={transactedAt}
              onChange={(e) => setTransactedAt(e.target.value)}
              className="w-full px-3.5 py-2 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-sm text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)] transition-colors"
            />
          </div>

          {error && (
            <div className="text-xs text-[var(--color-expense-dark)] bg-[var(--color-expense-bg)] px-3 py-2 rounded-lg border border-[var(--color-expense-stroke)]">
              {error}
            </div>
          )}

          {/* Action Buttons */}
          <div className="flex items-center justify-end gap-3 mt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs font-medium text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
            >
              取消
            </button>
            <button
              type="submit"
              disabled={submitting || (recordType === 'repayment' && liabilityMethods.length === 0)}
              className="px-5 py-2 rounded-lg bg-[var(--color-brand)] hover:bg-[var(--color-brand-hover)] text-white text-xs font-semibold cursor-pointer disabled:opacity-50 disabled:cursor-not-allowed transition-colors shadow-[0_2px_8px_rgba(0,120,212,0.3)]"
            >
              {submitting ? '保存中...' : initialTransaction ? '保存修改' : '记录此账单'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};
