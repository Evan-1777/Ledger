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
    type?: 'expense' | 'income' | 'repayment' | 'transfer';
    amount: number;
    fee?: number;
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
  const [recordType, setRecordType] = useState<'expense' | 'income' | 'transfer' | 'repayment'>('expense');
  const [amountStr, setAmountStr] = useState('');
  const [description, setDescription] = useState('');
  const [paymentMethodId, setPaymentMethodId] = useState<number>(0);
  const [sourcePaymentMethodId, setSourcePaymentMethodId] = useState<number | undefined>(undefined);
  const [categoryId, setCategoryId] = useState<number>(0);
  const [tagId, setTagId] = useState<number>(0);
  const [transactedAt, setTransactedAt] = useState('');

  // Inline Category Picker state (Inline Collapsible, eliminates small screen floating occlusion)
  const [inlineCatOpen, setInlineCatOpen] = useState(false);
  const [hoverCategoryId, setHoverCategoryId] = useState<number>(0);

  // Transfer Fee state (Variant A - Discreet Inline Collapsible)
  const [showFee, setShowFee] = useState(false);
  const [feeStr, setFeeStr] = useState('');

  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const amountInputRef = useRef<HTMLInputElement>(null);

  const assetMethods = paymentMethods.filter((pm) => pm.type === 'asset' || !pm.type);
  const liabilityMethods = paymentMethods.filter((pm) => pm.type === 'liability');

  // Initialize or reset when modal opens or initialTransaction changes
  useEffect(() => {
    if (!isOpen) {
      setInlineCatOpen(false);
      setError(null);
      setShowFee(false);
      setFeeStr('');
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

      if (initialType === 'transfer' && (initialTransaction.fee ?? 0) > 0) {
        setShowFee(true);
        setFeeStr(String(initialTransaction.fee));
      } else {
        setShowFee(false);
        setFeeStr('');
      }

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
      setShowFee(false);
      setFeeStr('');

      // Default payment method
      if (paymentMethods.length > 0) {
        setPaymentMethodId(paymentMethods[0].id);
      }

      // Default category and tag for expense
      const defaultExpCat = categories.find((c) => c.type === 'expense') ||
        categories.find((c) => c.name !== '债务偿还' && c.name !== '账户转账') ||
        categories[0];
      if (defaultExpCat) {
        setCategoryId(defaultExpCat.id);
        setHoverCategoryId(defaultExpCat.id);
        setTagId(defaultExpCat.tags?.[0]?.id || 0);
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

  // Keyboard shortcut: ESC to close
  useEffect(() => {
    function handleKeyDown(e: KeyboardEvent) {
      if (!isOpen) return;
      if (e.key === 'Escape') {
        if (inlineCatOpen) {
          setInlineCatOpen(false);
        } else {
          onClose();
        }
      }
    }
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isOpen, inlineCatOpen, onClose]);

  if (!isOpen) return null;

  const currentCategory = categories.find((c) => c.id === categoryId);
  const currentTag = currentCategory?.tags?.find((t) => t.id === tagId);

  const hoverCategory = categories.find((c) => c.id === hoverCategoryId) || currentCategory;

  const handleSwitchType = (newType: 'expense' | 'income' | 'transfer' | 'repayment') => {
    if (initialTransaction) return;
    setRecordType(newType);
    setInlineCatOpen(false);

    if (newType !== 'transfer') {
      setShowFee(false);
      setFeeStr('');
    }

    if (newType === 'transfer') {
      const transCat = categories.find((c) => c.name === '账户转账');
      if (transCat) {
        setCategoryId(transCat.id);
        setHoverCategoryId(transCat.id);
        setTagId(transCat.tags?.[0]?.id || 0);
      }
      // Target channel must be an asset channel
      let targetId = paymentMethodId;
      if (assetMethods.length > 0 && !assetMethods.some((pm) => pm.id === targetId)) {
        targetId = assetMethods[0].id;
        setPaymentMethodId(targetId);
      }
      // Source channel must be another asset channel
      const otherAsset = assetMethods.find((pm) => pm.id !== targetId);
      if (otherAsset) {
        setSourcePaymentMethodId(otherAsset.id);
      } else {
        setSourcePaymentMethodId(undefined);
      }
    } else if (newType === 'repayment') {
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
        setTagId(repCat.tags?.[0]?.id || 0);
      }
    } else if (newType === 'income') {
      if (assetMethods.length > 0 && !assetMethods.some((pm) => pm.id === paymentMethodId)) {
        setPaymentMethodId(assetMethods[0].id);
      }
      const incCat = categories.find((c) => c.type === 'income') || categories.find((c) => c.name === '职业收入');
      if (incCat) {
        setCategoryId(incCat.id);
        setHoverCategoryId(incCat.id);
        setTagId(incCat.tags?.[0]?.id || 0);
      }
      setSourcePaymentMethodId(undefined);
    } else {
      // Expense
      const expCat = categories.find((c) => c.type === 'expense') ||
        categories.find((c) => c.name !== '债务偿还' && c.name !== '账户转账') ||
        categories[0];
      if (expCat) {
        setCategoryId(expCat.id);
        setHoverCategoryId(expCat.id);
        setTagId(expCat.tags?.[0]?.id || 0);
      }
      if (paymentMethods.length > 0 && !paymentMethods.some((pm) => pm.id === paymentMethodId)) {
        setPaymentMethodId(paymentMethods[0].id);
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

    if (recordType === 'transfer') {
      if (!paymentMethodId || !sourcePaymentMethodId) {
        setError('请选择转出与转入资产账户');
        return;
      }
      if (paymentMethodId === sourcePaymentMethodId) {
        setError('转出账户与转入账户不能相同');
        return;
      }
    } else if (recordType === 'repayment') {
      if (!paymentMethodId) {
        setError('请选择还入负债账户');
        return;
      }
    } else {
      if (!paymentMethodId) {
        setError(recordType === 'income' ? '请选择存入渠道' : '请选择支付途径');
        return;
      }
    }

    let finalCatId = categoryId;
    let finalTagId = tagId;
    if (recordType === 'transfer') {
      const transCat = categories.find((c) => c.name === '账户转账');
      if (transCat) {
        finalCatId = transCat.id;
        finalTagId = transCat.tags?.[0]?.id || tagId;
      }
    } else if (recordType === 'repayment') {
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
    let finalFee: number | undefined = undefined;
    if (recordType === 'transfer') {
      if (showFee) {
        const trimmedFee = feeStr.trim();
        if (trimmedFee) {
          const parsedFee = parseFloat(trimmedFee);
          if (isNaN(parsedFee) || parsedFee < 0) {
            setError('请输入有效的手续费金额');
            return;
          }
          finalFee = parsedFee;
        } else {
          finalFee = 0;
        }
      } else {
        finalFee = 0;
      }
    }

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
        fee: finalFee,
        description: description.trim(),
        payment_method_id: paymentMethodId,
        source_payment_method_id: (recordType === 'repayment' || recordType === 'transfer') ? sourcePaymentMethodId : undefined,
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

  // Filter categories strictly for expense vs income
  const visibleCategories = categories.filter((c) => {
    if (recordType === 'income') {
      return c.type === 'income' || c.name === '职业收入';
    }
    return (c.type === 'expense' || !c.type) && c.name !== '债务偿还' && c.name !== '账户转账';
  });

  return (
    <div className="fixed inset-0 z-[1000] bg-black/45 backdrop-blur-sm flex items-center justify-center p-3 sm:p-4">
      {/* Modal Card - 100dvh Dynamic Viewport Height & Column Flex */}
      <div className="w-full max-w-[520px] max-h-[calc(100dvh-24px)] bg-[var(--color-card-bg)] rounded-2xl shadow-[var(--shadow-modal)] border border-[var(--color-neutral-stroke)] flex flex-col overflow-hidden animate-fade-in relative">
        {/* Header - Fixed flex-shrink-0 */}
        <div className="px-5 sm:px-6 py-4 border-b border-[var(--color-neutral-stroke)] flex items-center justify-between flex-shrink-0 bg-[var(--color-card-bg)]">
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

        {/* Form Container with Scrollable Body and Constant Footer */}
        <form onSubmit={handleFormSubmit} className="flex flex-col flex-1 min-h-0 overflow-hidden">
          {/* Scrollable Form Body - flex-1 overflow-y-auto */}
          <div className="p-4 sm:p-6 flex flex-col gap-4 overflow-y-auto flex-1 min-h-0">
            {/* Top 4-Segment Capsule Slider */}
            <div
              className={`relative bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke)] rounded-xl p-1 grid grid-cols-4 select-none ${
                initialTransaction ? 'opacity-85' : ''
              }`}
            >
              {/* Smooth hardware-accelerated sliding indicator */}
              <div
                className={`absolute top-1 bottom-1 left-1 w-[calc((100%-8px)/4)] rounded-lg transition-transform duration-200 ease-out shadow-sm ${
                  recordType === 'expense'
                    ? 'translate-x-0 bg-[var(--color-expense-bg)] border border-[var(--color-expense-stroke)]'
                    : recordType === 'income'
                    ? 'translate-x-full bg-[var(--color-income-bg)] border border-[var(--color-income-stroke)]'
                    : recordType === 'transfer'
                    ? 'translate-x-[200%] bg-[var(--color-brand-light)] border border-[var(--color-brand-stroke)]'
                    : 'translate-x-[300%] bg-[var(--color-brand-light)] border border-[var(--color-brand-stroke)]'
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
                onClick={() => handleSwitchType('transfer')}
                className={`relative z-10 py-2 text-center text-xs font-semibold transition-colors duration-150 ${
                  initialTransaction ? 'cursor-not-allowed' : 'cursor-pointer'
                } ${
                  recordType === 'transfer'
                    ? 'text-[var(--color-brand)]'
                    : 'text-[var(--color-neutral-fg-3)] hover:text-[var(--color-neutral-fg-1)]'
                }`}
              >
                ⇄ 转账
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
              <div className="mb-1.5 flex items-center justify-between">
                <span className="text-xs text-[var(--color-neutral-fg-3)]">账单金额</span>
                {recordType === 'transfer' && !showFee && (
                  <button
                    type="button"
                    onClick={() => setShowFee(true)}
                    className="text-[11px] font-medium text-[var(--color-neutral-fg-3)] hover:text-[var(--color-brand)] px-1.5 py-0.5 rounded transition-colors cursor-pointer"
                  >
                    + 手续费
                  </button>
                )}
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

              {/* Inline Collapsible Fee Row */}
              {recordType === 'transfer' && showFee && (
                <div className="mt-2.5 pt-2 border-t border-dashed border-[var(--color-neutral-stroke-strong)] flex items-center justify-between animate-fade-in">
                  <span className="text-xs font-medium text-[var(--color-neutral-fg-2)]">手续费</span>
                  <div className="flex items-center gap-1">
                    <span className="text-xs text-[var(--color-neutral-fg-3)]">¥</span>
                    <input
                      type="text"
                      inputMode="decimal"
                      value={feeStr}
                      onChange={(e) => {
                        const val = e.target.value;
                        if (/^\d*\.?\d*$/.test(val)) {
                          setFeeStr(val);
                        }
                      }}
                      placeholder="0.00"
                      className="w-20 text-right bg-transparent border-b border-[var(--color-neutral-stroke-strong)] focus:border-[var(--color-brand)] outline-none px-1 py-0.5 text-xs font-semibold text-[var(--color-neutral-fg-1)] tabular-nums transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => {
                        setFeeStr('');
                        setShowFee(false);
                      }}
                      className="p-1 text-[11px] text-[var(--color-neutral-fg-subtle)] hover:text-[var(--color-neutral-fg-1)] rounded hover:bg-[var(--color-hover-bg)] transition-colors cursor-pointer leading-none ml-0.5"
                      title="清除手续费"
                    >
                      ✕
                    </button>
                  </div>
                </div>
              )}
            </div>

            {/* Description */}
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">用途说明</label>
              <input
                type="text"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                placeholder={
                  recordType === 'transfer'
                    ? '如：银行卡转微信零钱、ATM 取现备用等'
                    : recordType === 'repayment'
                    ? '如：偿还招商信用卡当期账单'
                    : recordType === 'income'
                    ? '如：主业工资、投资分红等'
                    : '如：午餐商务简餐、地铁交通等'
                }
                className="w-full px-3.5 py-2 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] text-sm text-[var(--color-neutral-fg-1)] outline-none focus:border-[var(--color-brand)] transition-colors"
              />
            </div>

            {/* Category Section: Locked Card (Transfer / Repayment) OR Inline Progressive Disclosure (Expense / Income) */}
            {recordType === 'transfer' || recordType === 'repayment' ? (
              <div className="flex flex-col gap-1.5">
                <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">分类与细分标签</label>
                <div className="w-full px-3.5 py-2.5 rounded-lg bg-[var(--color-subtle-bg)] border border-[var(--color-neutral-stroke)] flex items-center justify-between text-xs select-none">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-[var(--color-neutral-fg-1)]">
                      {recordType === 'transfer' ? '账户转账' : '债务偿还'}
                    </span>
                    <span className="text-xs text-[var(--color-neutral-fg-subtle)]">·</span>
                    <span className="text-[var(--color-brand)] font-medium">
                      {recordType === 'transfer' ? '资金互转' : '负债还款'}
                    </span>
                  </div>
                  <div className="flex items-center gap-1 text-[11px] text-[var(--color-neutral-fg-3)]">
                    <LockIcon size={13} className="text-[var(--color-neutral-fg-3)]" />
                    <span>系统固定</span>
                  </div>
                </div>
              </div>
            ) : (
              <div className="flex flex-col gap-1.5">
                <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">分类与细分标签</label>
                <button
                  type="button"
                  onClick={() => setInlineCatOpen(!inlineCatOpen)}
                  className="w-full px-3.5 py-2.5 rounded-lg bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke-strong)] hover:border-[var(--color-brand)] flex items-center justify-between cursor-pointer transition-colors text-left"
                >
                  <div className="flex items-center gap-2 text-sm">
                    <span className="font-semibold text-[var(--color-neutral-fg-1)]">
                      {currentCategory?.name || '请选择分类'}
                    </span>
                    <span className="text-xs text-[var(--color-neutral-fg-subtle)]">›</span>
                    <span className="text-[var(--color-brand)] font-medium">
                      {currentTag?.name || '请选择标签'}
                    </span>
                  </div>
                  <ChevronDownIcon
                    size={14}
                    className={`text-[var(--color-neutral-fg-3)] transition-transform duration-150 ${inlineCatOpen ? 'rotate-180' : ''}`}
                  />
                </button>

                {/* Inline Collapsible Category & Tag Grid */}
                {inlineCatOpen && (
                  <div className="border border-[var(--color-neutral-stroke)] rounded-xl bg-[var(--color-subtle-bg)] p-3 flex flex-col gap-2.5 animate-fade-in">
                    <div>
                      <div className="text-[11px] font-medium text-[var(--color-neutral-fg-3)] mb-1.5">
                        {recordType === 'income' ? '收入分类' : '支出分类'}
                      </div>
                      <div className="flex flex-wrap gap-1.5">
                        {visibleCategories.map((cat) => {
                          const isHovered = cat.id === (hoverCategory?.id || currentCategory?.id);
                          return (
                            <button
                              key={cat.id}
                              type="button"
                              onClick={() => {
                                setHoverCategoryId(cat.id);
                              }}
                              className={`px-2.5 py-1 rounded-lg text-xs font-medium cursor-pointer transition-all ${
                                isHovered
                                  ? 'bg-[var(--color-brand-light)] border border-[var(--color-brand-stroke)] text-[var(--color-brand)] font-semibold shadow-xs'
                                  : 'bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)]'
                              }`}
                            >
                              {cat.name}
                            </button>
                          );
                        })}
                      </div>
                    </div>

                    <div className="h-[1px] bg-[var(--color-neutral-stroke)]" />

                    <div>
                      <div className="text-[11px] font-medium text-[var(--color-neutral-fg-3)] mb-1.5">
                        {hoverCategory?.name} · 细分标签
                      </div>
                      <div className="flex flex-wrap gap-1.5">
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
                                  setInlineCatOpen(false);
                                }}
                                className={`px-2.5 py-1 rounded-lg text-xs font-medium cursor-pointer transition-all ${
                                  isSelected
                                    ? 'bg-[var(--color-brand)] text-white font-semibold shadow-xs'
                                    : 'bg-[var(--color-card-bg)] border border-[var(--color-neutral-stroke)] text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)]'
                                }`}
                              >
                                {tg.name}
                              </button>
                            );
                          })
                        ) : (
                          <span className="text-xs text-[var(--color-neutral-fg-subtle)]">暂无细分标签</span>
                        )}
                      </div>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* Channels Selection depending on recordType */}
            {recordType === 'transfer' ? (
              <>
                {/* Source Asset Channel */}
                <div className="flex flex-col gap-1.5">
                  <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">转出资产账户</label>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    {assetMethods.map((pm) => {
                      const isSelected = pm.id === sourcePaymentMethodId;
                      const isTarget = pm.id === paymentMethodId;
                      return (
                        <button
                          key={pm.id}
                          type="button"
                          disabled={isTarget}
                          onClick={() => setSourcePaymentMethodId(pm.id)}
                          className={`py-2 px-1 rounded-lg text-xs font-medium border text-center cursor-pointer transition-all ${
                            isSelected
                              ? 'border-[var(--color-brand)] bg-[var(--color-brand-light)] text-[var(--color-brand)] font-semibold'
                              : isTarget
                              ? 'border-[var(--color-neutral-stroke)] bg-[var(--color-subtle-bg)] text-[var(--color-neutral-fg-subtle)] cursor-not-allowed opacity-40'
                              : 'border-[var(--color-neutral-stroke-strong)] bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)]'
                          }`}
                        >
                          {pm.name}
                        </button>
                      );
                    })}
                  </div>
                </div>

                {/* Target Asset Channel */}
                <div className="flex flex-col gap-1.5">
                  <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">转入资产账户</label>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    {assetMethods.map((pm) => {
                      const isSelected = pm.id === paymentMethodId;
                      const isSource = pm.id === sourcePaymentMethodId;
                      return (
                        <button
                          key={pm.id}
                          type="button"
                          disabled={isSource}
                          onClick={() => setPaymentMethodId(pm.id)}
                          className={`py-2 px-1 rounded-lg text-xs font-medium border text-center cursor-pointer transition-all ${
                            isSelected
                              ? 'border-[var(--color-brand)] bg-[var(--color-brand-light)] text-[var(--color-brand)] font-semibold'
                              : isSource
                              ? 'border-[var(--color-neutral-stroke)] bg-[var(--color-subtle-bg)] text-[var(--color-neutral-fg-subtle)] cursor-not-allowed opacity-40'
                              : 'border-[var(--color-neutral-stroke-strong)] bg-[var(--color-card-bg)] text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)]'
                          }`}
                        >
                          {pm.name}
                        </button>
                      );
                    })}
                  </div>
                </div>
              </>
            ) : recordType === 'repayment' ? (
              <>
                {/* Target Liability Channel */}
                <div className="flex flex-col gap-1.5">
                  <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">还入负债账户</label>
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
                  <label className="text-xs font-medium text-[var(--color-neutral-fg-2)]">转出资产账户</label>
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
          </div>

          {/* Root-cause fix: Pinned constant Footer - flex-shrink-0 border-t */}
          <div className="px-5 sm:px-6 py-3.5 border-t border-[var(--color-neutral-stroke)] bg-[var(--color-card-bg)] flex items-center justify-end gap-3 flex-shrink-0">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-lg border border-[var(--color-neutral-stroke-strong)] text-xs font-medium text-[var(--color-neutral-fg-2)] hover:bg-[var(--color-hover-bg)] cursor-pointer transition-colors"
            >
              取消
            </button>
            <button
              type="submit"
              disabled={
                submitting ||
                (recordType === 'repayment' && liabilityMethods.length === 0) ||
                (recordType === 'transfer' && assetMethods.length < 2)
              }
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
