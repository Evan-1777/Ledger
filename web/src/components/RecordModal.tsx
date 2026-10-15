import { useState, useEffect, useRef, useId } from 'react';
import type { FC, FormEvent } from 'react';
import {
  CloseIcon,
  ChevronDownIcon,
  ChevronRightIcon,
  LockIcon,
  ExpenseIcon,
  IncomeIcon,
  TransferIcon,
  RepaymentIcon,
} from './Icons';
import { SegmentedControl, Button } from './primitives';
import { Category, PaymentMethod, Transaction } from '../lib/api';
import { toLocalInputValue, fromLocalInputValue } from '../lib/format.ts';

type RecordType = 'expense' | 'income' | 'transfer' | 'repayment';

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

const INPUT_CLASS =
  'w-full px-3 py-2 rounded-[var(--r-sm)] bg-[var(--surface)] border border-[var(--line-strong)] ' +
  'text-[16px] min-[640px]:text-[13.5px] text-[var(--fg)] outline-none placeholder:text-[var(--fg-muted)] ' +
  'focus:border-[var(--brand)] focus:shadow-[0_0_0_3px_var(--brand-soft)] ' +
  'transition-[border-color,box-shadow] duration-[var(--d1)]';

export const RecordModal: FC<RecordModalProps> = ({
  isOpen,
  onClose,
  onNavigateToSettings,
  categories,
  paymentMethods,
  initialTransaction,
  onSubmit,
}) => {
  const [recordType, setRecordType] = useState<RecordType>('expense');
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

  // Channels a record type may target; the first entry is the default selection
  const targetChannels = (type: RecordType) =>
    type === 'repayment' ? liabilityMethods : type === 'expense' ? paymentMethods : assetMethods;

  // Track recordType via ref for the fallback effect without triggering unwanted re-runs
  const recordTypeRef = useRef(recordType);
  recordTypeRef.current = recordType;

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

      setTransactedAt(toLocalInputValue(initialTransaction.transacted_at));
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
      } else {
        setPaymentMethodId(0);
      }

      // Default category and tag for expense
      const defaultExpCat = categories.find((c) => c.type === 'expense') ||
        categories.find((c) => c.name !== '债务偿还' && c.name !== '账户转账') ||
        categories[0];
      if (defaultExpCat) {
        setCategoryId(defaultExpCat.id);
        setHoverCategoryId(defaultExpCat.id);
        setTagId(defaultExpCat.tags?.[0]?.id || 0);
      } else {
        setCategoryId(0);
        setHoverCategoryId(0);
        setTagId(0);
      }

      setTransactedAt(toLocalInputValue(new Date().toISOString()));
    }

    const timer = setTimeout(() => {
      amountInputRef.current?.focus();
    }, 50);
    return () => clearTimeout(timer);
  }, [isOpen, initialTransaction]);

  // Fill defaults if config data arrives after modal was opened
  useEffect(() => {
    if (!isOpen || initialTransaction) return;

    setPaymentMethodId((prev) => (prev === 0 ? (targetChannels(recordTypeRef.current)[0]?.id ?? 0) : prev));

    setCategoryId((prev) => {
      if (prev === 0 && categories.length > 0) {
        const targetType = recordTypeRef.current === 'income' ? 'income' : 'expense';
        const defaultCat =
          categories.find((c) => c.type === targetType) ||
          categories.find((c) => c.name !== '债务偿还' && c.name !== '账户转账') ||
          categories[0];
        if (defaultCat) {
          setHoverCategoryId(defaultCat.id);
          setTagId(defaultCat.tags?.[0]?.id || 0);
          return defaultCat.id;
        }
      }
      return prev;
    });
  }, [isOpen, categories, paymentMethods]);

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

  const handleSwitchType = (newType: RecordType) => {
    if (initialTransaction) return;
    setRecordType(newType);
    setInlineCatOpen(false);

    if (newType !== 'transfer') {
      setShowFee(false);
      setFeeStr('');
    }

    // Target channel must belong to the type's own list; reassign only when the current one is invalid
    const targets = targetChannels(newType);
    const targetId = targets.length > 0 && !targets.some((pm) => pm.id === paymentMethodId)
      ? targets[0].id
      : paymentMethodId;
    if (targetId !== paymentMethodId) {
      setPaymentMethodId(targetId);
    }

    if (newType === 'transfer') {
      const transCat = categories.find((c) => c.name === '账户转账');
      if (transCat) {
        setCategoryId(transCat.id);
        setHoverCategoryId(transCat.id);
        setTagId(transCat.tags?.[0]?.id || 0);
      }
      // Source channel must be another asset channel
      setSourcePaymentMethodId(targets.find((pm) => pm.id !== targetId)?.id);
    } else if (newType === 'repayment') {
      setSourcePaymentMethodId(assetMethods[0]?.id);
      const repCat = categories.find((c) => c.name === '债务偿还');
      if (repCat) {
        setCategoryId(repCat.id);
        setHoverCategoryId(repCat.id);
        setTagId(repCat.tags?.[0]?.id || 0);
      }
    } else if (newType === 'income') {
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
          if (isNaN(parsedFee)) {
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

    const finalTransactedAt = transactedAt ? fromLocalInputValue(transactedAt) : '';
    if (transactedAt && !finalTransactedAt) {
      setError('请输入有效的记账时间');
      return;
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
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : '保存失败');
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

  const TYPE_ITEMS = [
    { key: 'expense', label: '支出', icon: <ExpenseIcon size={14} /> },
    { key: 'income', label: '收入', icon: <IncomeIcon size={14} /> },
    { key: 'transfer', label: '转账', icon: <TransferIcon size={14} /> },
    { key: 'repayment', label: '还款', icon: <RepaymentIcon size={14} /> },
  ];

  return (
    <div className="fixed inset-0 z-[1000] bg-[var(--overlay)] backdrop-blur-[4px] flex items-center justify-center p-3 sm:p-4 animate-fade">
      {/* Modal Card - 100dvh Dynamic Viewport Height & Column Flex */}
      <div
        role="dialog"
        aria-modal="true"
        aria-label={initialTransaction ? '编辑账单' : '记账'}
        className="w-full max-w-[520px] max-h-[calc(100dvh-24px)] bg-[var(--surface)] border border-[var(--line)] rounded-[var(--r-xl)] shadow-[var(--e4),inset_0_1px_0_var(--highlight-top)] flex flex-col overflow-hidden animate-pop relative"
      >
        {/* Header */}
        <div className="px-[18px] py-3.5 border-b border-[var(--line)] flex items-center justify-between flex-shrink-0">
          <b className="text-[15px] font-[650] text-[var(--fg)]">{initialTransaction ? '编辑账单' : '记账'}</b>
          <button
            type="button"
            aria-label="关闭"
            onClick={onClose}
            className="w-[34px] h-[34px] rounded-[var(--r-sm)] flex items-center justify-center text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-hover)] cursor-pointer transition-colors duration-[var(--d1)]"
          >
            <CloseIcon size={15} />
          </button>
        </div>

        <form onSubmit={handleFormSubmit} className="flex flex-col flex-1 min-h-0 overflow-hidden">
          {/* Scrollable Form Body */}
          <div className="p-[18px] flex flex-col gap-3.5 overflow-y-auto flex-1 min-h-0">
            {/* 4-Segment Type Slider with shared-position indicator */}
            <div className={initialTransaction ? 'opacity-60' : ''}>
              <SegmentedControl
                items={TYPE_ITEMS}
                value={recordType}
                onChange={(key) => handleSwitchType(key as RecordType)}
                ariaLabel="记账类型"
                compact="xs"
                disabled={!!initialTransaction}
                className="rounded-[var(--r-md)]"
              />
            </div>

            {/* Hero Amount Box — the single protagonist */}
            <div className="p-3.5 px-4 rounded-[var(--r-md)] bg-[var(--surface-sunken)] border border-[var(--line)] focus-within:border-[var(--brand)] focus-within:bg-[var(--surface)] transition-[border-color,background-color] duration-[var(--d1)]">
              <div className="mb-1 flex items-center justify-between">
                <label htmlFor="record-amount" className="text-xs text-[var(--fg-3)]">账单金额</label>
                {recordType === 'transfer' && !showFee && (
                  <button
                    type="button"
                    onClick={() => setShowFee(true)}
                    className="text-[11.5px] font-semibold text-[var(--fg-3)] hover:text-[var(--brand-text)] hover:bg-[var(--brand-soft)] px-1.5 py-0.5 rounded-[var(--r-xs)] transition-colors cursor-pointer"
                  >
                    + 手续费
                  </button>
                )}
              </div>
              <div className="flex items-baseline gap-1.5">
                <span className="text-[22px] font-medium text-[var(--fg-2)]">¥</span>
                <input
                  ref={amountInputRef}
                  id="record-amount"
                  type="text"
                  inputMode="decimal"
                  value={amountStr}
                  onChange={(e) => handleAmountChange(e.target.value)}
                  placeholder="0.00"
                  className="flex-1 min-w-0 bg-transparent border-none outline-none text-[34px] font-[680] tracking-[-.03em] text-[var(--fg)] num placeholder:text-[var(--fg-muted)]"
                />
              </div>

              {/* Inline Collapsible Fee Row */}
              {recordType === 'transfer' && showFee && (
                <div className="mt-2.5 pt-2.5 border-t border-dashed border-[var(--line-strong)] flex items-center justify-between animate-fade">
                  <span className="text-xs font-semibold text-[var(--fg-2)]">手续费</span>
                  <div className="flex items-center gap-1">
                    <span className="text-xs text-[var(--fg-3)]">¥</span>
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
                      aria-label="手续费"
                      className="w-20 text-right bg-transparent border-b border-[var(--line-strong)] focus:border-[var(--brand)] outline-none px-1 py-0.5 text-[13px] font-semibold text-[var(--fg)] num transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => {
                        setFeeStr('');
                        setShowFee(false);
                      }}
                      className="p-1 text-[11px] text-[var(--fg-muted)] hover:text-[var(--fg)] rounded hover:bg-[var(--surface-hover)] transition-colors cursor-pointer leading-none ml-0.5"
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
              <label htmlFor="record-desc" className="text-xs font-semibold text-[var(--fg-2)]">用途说明</label>
              <input
                id="record-desc"
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
                className={INPUT_CLASS}
              />
            </div>

            {/* Category Section: Locked Card (Transfer / Repayment) OR Inline Progressive Disclosure */}
            {recordType === 'transfer' || recordType === 'repayment' ? (
              <div className="flex flex-col gap-1.5">
                <label className="text-xs font-semibold text-[var(--fg-2)]">分类与细分标签</label>
                <div className="w-full px-3 py-2.5 rounded-[var(--r-sm)] bg-[var(--surface-sunken)] border border-[var(--line)] flex items-center justify-between text-[13px] select-none">
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-[var(--fg)]">
                      {recordType === 'transfer' ? '账户转账' : '债务偿还'}
                    </span>
                    <span className="text-xs text-[var(--fg-muted)]">·</span>
                    <span className="text-[var(--brand-text)] font-medium">
                      {recordType === 'transfer' ? '资金互转' : '负债还款'}
                    </span>
                  </div>
                  <div className="flex items-center gap-1 text-[11.5px] text-[var(--fg-3)]">
                    <LockIcon size={13} />
                    <span>系统固定</span>
                  </div>
                </div>
              </div>
            ) : (
              <div className="flex flex-col gap-1.5">
                <label className="text-xs font-semibold text-[var(--fg-2)]">分类与细分标签</label>
                <button
                  type="button"
                  onClick={() => setInlineCatOpen(!inlineCatOpen)}
                  className="w-full px-3 py-2.5 rounded-[var(--r-sm)] bg-[var(--surface)] border border-[var(--line-strong)] hover:border-[var(--brand)] flex items-center justify-between cursor-pointer transition-colors duration-[var(--d1)] text-left text-[13.5px]"
                >
                  <div className="flex items-center gap-2">
                    <span className="font-semibold text-[var(--fg)]">
                      {currentCategory?.name || '请选择分类'}
                    </span>
                    <ChevronRight />
                    <span className="text-[var(--brand-text)] font-medium">
                      {currentTag?.name || '请选择标签'}
                    </span>
                  </div>
                  <ChevronDownIcon
                    size={14}
                    className={`text-[var(--fg-3)] transition-transform duration-[var(--d2)] [transition-timing-function:var(--ease-out)] ${inlineCatOpen ? 'rotate-180' : ''}`}
                  />
                </button>

                {/* Inline Collapsible Category & Tag Grid */}
                {inlineCatOpen && (
                  <div className="border border-[var(--line)] rounded-[var(--r-md)] bg-[var(--surface-sunken)] p-3 flex flex-col gap-2.5 animate-fade">
                    <div>
                      <div className="text-[11px] font-semibold text-[var(--fg-3)] mb-1.5">
                        {recordType === 'income' ? '收入分类' : '支出分类'}
                      </div>
                      <div className="flex flex-wrap gap-1.5">
                        {visibleCategories.map((cat) => {
                          const isHovered = cat.id === (hoverCategory?.id || currentCategory?.id);
                          return (
                            <button
                              key={cat.id}
                              type="button"
                              aria-pressed={isHovered}
                              onClick={() => setHoverCategoryId(cat.id)}
                              className={`px-2.5 py-1 rounded-[var(--r-sm)] text-xs font-medium cursor-pointer transition-all duration-[var(--d1)] ${
                                isHovered
                                  ? 'bg-[var(--brand-soft)] border border-[var(--brand-line)] text-[var(--brand-text)] font-semibold'
                                  : 'bg-[var(--surface)] border border-[var(--line)] text-[var(--fg-2)] hover:bg-[var(--surface-hover)]'
                              }`}
                            >
                              {cat.name}
                            </button>
                          );
                        })}
                      </div>
                    </div>

                    <div className="h-px bg-[var(--line)]" />

                    <div>
                      <div className="text-[11px] font-semibold text-[var(--fg-3)] mb-1.5">
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
                                aria-pressed={isSelected}
                                onClick={() => {
                                  setCategoryId(hoverCategory.id);
                                  setTagId(tg.id);
                                  setInlineCatOpen(false);
                                }}
                                className={`px-2.5 py-1 rounded-[var(--r-sm)] text-xs font-medium cursor-pointer transition-all duration-[var(--d1)] ${
                                  isSelected
                                    ? 'bg-[var(--brand)] border border-[var(--brand)] text-white font-semibold'
                                    : 'bg-[var(--surface)] border border-[var(--line)] text-[var(--fg-2)] hover:bg-[var(--surface-hover)]'
                                }`}
                              >
                                {tg.name}
                              </button>
                            );
                          })
                        ) : (
                          <span className="text-xs text-[var(--fg-muted)]">暂无细分标签</span>
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
                <ChannelField label="转出资产账户">
                  {assetMethods.map((pm) => {
                    const isSelected = pm.id === sourcePaymentMethodId;
                    const isTarget = pm.id === paymentMethodId;
                    return (
                      <ChannelButton
                        key={pm.id}
                        name={pm.name}
                        selected={isSelected}
                        disabled={isTarget}
                        onClick={() => setSourcePaymentMethodId(pm.id)}
                      />
                    );
                  })}
                </ChannelField>

                <ChannelField label="转入资产账户">
                  {assetMethods.map((pm) => {
                    const isSelected = pm.id === paymentMethodId;
                    const isSource = pm.id === sourcePaymentMethodId;
                    return (
                      <ChannelButton
                        key={pm.id}
                        name={pm.name}
                        selected={isSelected}
                        disabled={isSource}
                        onClick={() => setPaymentMethodId(pm.id)}
                      />
                    );
                  })}
                </ChannelField>
              </>
            ) : recordType === 'repayment' ? (
              <>
                <ChannelField label="还入负债账户">
                  {liabilityMethods.length === 0 ? (
                    <div className="col-span-2 min-[480px]:col-span-4 px-3 py-2.5 rounded-[var(--r-sm)] bg-[var(--surface-sunken)] border border-[var(--line)] text-xs text-[var(--fg-2)] flex items-center justify-between gap-2">
                      <span>暂无负债渠道，无法记录还款</span>
                      {onNavigateToSettings && (
                        <button
                          type="button"
                          onClick={onNavigateToSettings}
                          className="text-xs font-semibold text-[var(--brand-text)] hover:underline cursor-pointer flex-shrink-0"
                        >
                          前往设置添加 →
                        </button>
                      )}
                    </div>
                  ) : (
                    liabilityMethods.map((pm) => (
                      <ChannelButton
                        key={pm.id}
                        name={pm.name}
                        selected={pm.id === paymentMethodId}
                        onClick={() => setPaymentMethodId(pm.id)}
                      />
                    ))
                  )}
                </ChannelField>

                <ChannelField label="转出资产账户">
                  {assetMethods.map((pm) => (
                    <ChannelButton
                      key={pm.id}
                      name={pm.name}
                      selected={pm.id === sourcePaymentMethodId}
                      onClick={() => setSourcePaymentMethodId(pm.id)}
                    />
                  ))}
                  <ChannelButton
                    name="外部/未记录资金"
                    selected={sourcePaymentMethodId === undefined}
                    onClick={() => setSourcePaymentMethodId(undefined)}
                  />
                </ChannelField>
              </>
            ) : (
              <ChannelField label={recordType === 'income' ? '存入渠道' : '支付途径'}>
                {(recordType === 'income' ? assetMethods : paymentMethods).map((pm) => (
                  <ChannelButton
                    key={pm.id}
                    name={pm.name}
                    selected={pm.id === paymentMethodId}
                    onClick={() => setPaymentMethodId(pm.id)}
                  />
                ))}
              </ChannelField>
            )}

            {/* Date & Time */}
            <div className="flex flex-col gap-1.5">
              <label htmlFor="record-time" className="text-xs font-semibold text-[var(--fg-2)]">记账时间</label>
              <input
                id="record-time"
                type="datetime-local"
                value={transactedAt}
                onChange={(e) => setTransactedAt(e.target.value)}
                className={INPUT_CLASS}
              />
            </div>

            {error && (
              <div className="text-[12.5px] font-medium text-[var(--expense-text)] bg-[var(--expense-soft)] border border-[var(--expense-line)] px-3 py-2 rounded-[var(--r-sm)]">
                {error}
              </div>
            )}
          </div>

          {/* Pinned constant Footer */}
          <div className="px-[18px] py-3 border-t border-[var(--line)] flex items-center justify-end gap-2 flex-shrink-0">
            <Button variant="ghost" size="md" onClick={onClose} disabled={submitting}>
              取消
            </Button>
            <Button
              type="submit"
              variant="primary"
              size="md"
              disabled={
                submitting ||
                (recordType === 'repayment' && liabilityMethods.length === 0) ||
                (recordType === 'transfer' && assetMethods.length < 2)
              }
            >
              {submitting ? '保存中…' : initialTransaction ? '保存修改' : '记录此账单'}
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
};

/* ---- local field helpers ---- */

const ChevronRight = () => <ChevronRightIcon size={12} className="text-[var(--fg-muted)]" />;

const ChannelField: FC<{ label: string; children: React.ReactNode }> = ({ label, children }) => {
  const id = useId();
  return (
    <div className="flex flex-col gap-1.5">
      <span id={id} className="text-xs font-semibold text-[var(--fg-2)]">{label}</span>
      <div role="group" aria-labelledby={id} className="grid grid-cols-2 min-[480px]:grid-cols-4 gap-2">{children}</div>
    </div>
  );
};

const ChannelButton: FC<{
  name: string;
  selected: boolean;
  disabled?: boolean;
  onClick: () => void;
}> = ({ name, selected, disabled, onClick }) => (
  <button
    type="button"
    aria-pressed={selected}
    disabled={disabled}
    onClick={onClick}
    className={`py-2 px-1 rounded-[var(--r-sm)] text-xs font-medium border text-center cursor-pointer transition-all duration-[var(--d1)] ${
      selected
        ? 'border-[var(--brand)] bg-[var(--brand-soft)] text-[var(--brand-text)] font-semibold'
        : disabled
        ? 'border-[var(--line)] bg-[var(--surface-sunken)] text-[var(--fg-muted)] cursor-not-allowed opacity-40'
        : 'border-[var(--line-strong)] bg-[var(--surface)] text-[var(--fg-2)] hover:bg-[var(--surface-hover)]'
    }`}
  >
    {name}
  </button>
);
