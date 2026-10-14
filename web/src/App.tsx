import { useState, useEffect, useCallback } from 'react';
import { Navbar, TabType } from './components/Navbar';
import { BottomBar, FilterType } from './components/BottomBar';
import { AuthModal } from './components/AuthModal';
import { RecordModal } from './components/RecordModal';
import { Toast, ToastMessage } from './components/Toast';
import { ConfirmDialog } from './components/primitives';
import { StreamPage } from './pages/StreamPage';
import { StatsPage } from './pages/StatsPage';
import { SettingsPage } from './pages/SettingsPage';
import {
  api,
  Category,
  PaymentMethod,
  Transaction,
  StatsSummary,
  onAuthStateChange,
} from './lib/api';

interface PendingDelete {
  id: number;
  summary: string;
}

export default function App() {
  // Theme state
  const [darkMode, setDarkMode] = useState<boolean>(() => {
    return localStorage.getItem('ledger_theme') === 'dark';
  });

  // Auth state
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(false);
  const [showAuthModal, setShowAuthModal] = useState<boolean>(false);

  // Tab & Filter state
  const [currentTab, setCurrentTab] = useState<TabType>('stream');
  const [streamFilter, setStreamFilter] = useState<FilterType>('all');

  // Business Data
  const [categories, setCategories] = useState<Category[]>([]);
  const [paymentMethods, setPaymentMethods] = useState<PaymentMethod[]>([]);
  const [transactions, setTransactions] = useState<Transaction[]>([]);
  const [monthTransactions, setMonthTransactions] = useState<Transaction[]>([]);
  const [stats, setStats] = useState<StatsSummary | null>(null);

  // Loading states
  const [loadingTransactions, setLoadingTransactions] = useState(false);
  const [loadingStats, setLoadingStats] = useState(false);

  // Modals & Toasts
  const [isRecordModalOpen, setIsRecordModalOpen] = useState(false);
  const [editingTransaction, setEditingTransaction] = useState<Transaction | null>(null);
  const [pendingDelete, setPendingDelete] = useState<PendingDelete | null>(null);
  const [deleting, setDeleting] = useState(false);
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  const addToast = (type: 'success' | 'error' | 'info', message: string) => {
    const id = Math.random().toString(36).substring(2, 9);
    setToasts((prev) => [...prev, { id, type, message }]);
    setTimeout(() => {
      setToasts((prev) => prev.filter((t) => t.id !== id));
    }, 3500);
  };

  const removeToast = (id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  };

  // Sync theme on <html> so the pre-paint script in index.html stays consistent
  useEffect(() => {
    document.documentElement.classList.toggle('dark-mode', darkMode);
    localStorage.setItem('ledger_theme', darkMode ? 'dark' : 'light');
    // Browser chrome & native controls follow the app theme, not the OS preference
    const canvas = getComputedStyle(document.documentElement).getPropertyValue('--canvas').trim();
    if (canvas) {
      document.querySelector('meta[name="theme-color"]')?.setAttribute('content', canvas);
    }
    // Brief global transition to smooth the theme switch without lingering side effects
    document.body.classList.add('theme-switching');
    const t = setTimeout(() => document.body.classList.remove('theme-switching'), 200);
    return () => clearTimeout(t);
  }, [darkMode]);

  // Auth check and listener
  useEffect(() => {
    onAuthStateChange((auth) => {
      setIsAuthenticated(auth);
      if (!auth) {
        setShowAuthModal(true);
      }
    });

    api.checkAuth().then((auth) => {
      setIsAuthenticated(auth);
      if (!auth) {
        setShowAuthModal(true);
      }
    });
  }, []);

  // Fetch functions
  const fetchConfigData = useCallback(async () => {
    try {
      const [cats, pms] = await Promise.all([
        api.getCategories(),
        api.getPaymentMethods(),
      ]);
      setCategories(cats);
      setPaymentMethods(pms);
    } catch {
      // Ignored if unauthorized
    }
  }, []);

  const fetchTransactions = useCallback(async () => {
    setLoadingTransactions(true);
    try {
      // Headline and list are decoupled: the month aggregate always uses the unfiltered source
      const [data, monthData] = await Promise.all([
        api.getTransactions(streamFilter),
        api.getTransactions('all'),
      ]);
      setTransactions(data);
      setMonthTransactions(monthData);
    } catch (err: unknown) {
      if (isAuthenticated) {
        addToast('error', err instanceof Error ? err.message : '获取流水失败');
      }
    } finally {
      setLoadingTransactions(false);
    }
  }, [streamFilter, isAuthenticated]);

  const fetchStats = useCallback(async () => {
    setLoadingStats(true);
    try {
      const data = await api.getStatsSummary();
      setStats(data);
    } catch (err: unknown) {
      if (isAuthenticated) {
        addToast('error', err instanceof Error ? err.message : '获取统计失败');
      }
    } finally {
      setLoadingStats(false);
    }
  }, [isAuthenticated]);

  // Trigger loads when authenticated
  useEffect(() => {
    if (isAuthenticated) {
      fetchConfigData();
    }
  }, [isAuthenticated, fetchConfigData]);

  useEffect(() => {
    if (isAuthenticated && currentTab === 'stream') {
      fetchTransactions();
    }
  }, [isAuthenticated, currentTab, fetchTransactions]);

  useEffect(() => {
    if (isAuthenticated && currentTab === 'stats') {
      fetchStats();
    }
  }, [isAuthenticated, currentTab, fetchStats]);

  // Keyboard shortcut: N to record
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (
        (e.key === 'n' || e.key === 'N') &&
        !isRecordModalOpen &&
        !showAuthModal &&
        !document.querySelector('[aria-modal="true"]') &&
        document.activeElement?.tagName !== 'INPUT' &&
        document.activeElement?.tagName !== 'TEXTAREA'
      ) {
        e.preventDefault();
        setEditingTransaction(null);
        setIsRecordModalOpen(true);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [isRecordModalOpen, showAuthModal]);

  // Handlers for Transactions
  const handleSaveTransaction = async (data: {
    type?: 'expense' | 'income' | 'repayment' | 'transfer';
    amount: number;
    fee?: number;
    description: string;
    payment_method_id: number;
    source_payment_method_id?: number;
    category_id: number;
    tag_id: number;
    transacted_at: string;
  }) => {
    if (editingTransaction) {
      await api.updateTransaction(editingTransaction.id, data);
      addToast('success', '账单修改成功');
    } else {
      await api.createTransaction(data);
      addToast('success', '记账成功');
    }
    fetchTransactions();
    if (currentTab === 'stats') fetchStats();
  };

  const handleConfirmDelete = async () => {
    if (!pendingDelete) return;
    setDeleting(true);
    try {
      await api.deleteTransaction(pendingDelete.id);
      addToast('success', '账单已删除');
      setPendingDelete(null);
      fetchTransactions();
      if (currentTab === 'stats') fetchStats();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '删除失败');
      setPendingDelete(null);
    } finally {
      setDeleting(false);
    }
  };

  const handleEditClick = (tx: Transaction) => {
    setEditingTransaction(tx);
    setIsRecordModalOpen(true);
  };

  // Handlers for Settings
  const handleAddPaymentMethod = async (
    name: string,
    type: 'asset' | 'liability' = 'asset',
    initialBalance: number = 0,
    creditLimit: number = 0
  ) => {
    try {
      await api.createPaymentMethod(name, paymentMethods.length + 1, type, initialBalance, creditLimit);
      addToast('success', `${type === 'liability' ? '负债渠道' : '资产渠道'}「${name}」已添加`);
      fetchConfigData();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '添加失败');
      throw err;
    }
  };

  const handleUpdatePaymentMethod = async (
    id: number,
    name: string,
    sortOrder: number,
    type: 'asset' | 'liability',
    initialBalance: number,
    creditLimit: number
  ) => {
    try {
      await api.updatePaymentMethod(id, name, sortOrder, type, initialBalance, creditLimit);
      addToast('success', `渠道「${name}」已更新`);
      fetchConfigData();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '更新失败');
      throw err;
    }
  };

  const handleDeletePaymentMethod = async (id: number) => {
    try {
      await api.deletePaymentMethod(id);
      addToast('success', '渠道已删除');
      fetchConfigData();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '删除失败');
    }
  };

  const handleAddCategory = async (name: string, type: 'expense' | 'income' = 'expense') => {
    try {
      await api.createCategory(name, categories.length + 1, type);
      addToast('success', `${type === 'income' ? '收入分类' : '消费类型'}「${name}」已创建`);
      fetchConfigData();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '创建失败');
    }
  };

  const handleDeleteCategory = async (id: number) => {
    try {
      await api.deleteCategory(id);
      addToast('success', '消费类型已删除');
      fetchConfigData();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '删除失败');
    }
  };

  const handleUpdateCategory = async (id: number, name: string, sort_order: number, type?: 'expense' | 'income') => {
    try {
      await api.updateCategory(id, name, sort_order, type);
      fetchConfigData();
    } catch (err: unknown) {
      const msg = err instanceof Error && err.message?.includes('category already exists')
        ? '分类名称已存在'
        : err instanceof Error ? err.message : '更新分类失败';
      addToast('error', msg);
      fetchConfigData();
      throw err;
    }
  };

  const handleReorderCategories = async (
    updates: { id: number; name: string; sort_order: number }[]
  ) => {
    try {
      for (const item of updates) {
        await api.updateCategory(item.id, item.name, item.sort_order);
      }
      await fetchConfigData();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '调整分类顺序失败');
      await fetchConfigData();
      throw err;
    }
  };

  const handleAddTag = async (categoryId: number, name: string) => {
    try {
      await api.createTag(categoryId, name, 0);
      addToast('success', `细分标签「${name}」已添加`);
      fetchConfigData();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '添加失败');
      throw err;
    }
  };

  const handleUpdateTag = async (id: number, name: string, sort_order: number) => {
    try {
      await api.updateTag(id, name, sort_order);
      fetchConfigData();
    } catch (err: unknown) {
      const msg = err instanceof Error && err.message?.includes('tag already exists')
        ? '该分类下已存在同名标签'
        : err instanceof Error ? err.message : '更新细分标签失败';
      addToast('error', msg);
      fetchConfigData();
      throw err;
    }
  };

  const handleDeleteTag = async (id: number) => {
    try {
      await api.deleteTag(id);
      addToast('success', '细分标签已删除');
      fetchConfigData();
    } catch (err: unknown) {
      addToast('error', err instanceof Error ? err.message : '删除失败');
    }
  };

  return (
    <div className="min-h-screen flex flex-col bg-[var(--canvas)] text-[var(--fg)]">
      {/* Toast notifications */}
      <Toast toasts={toasts} onDismiss={removeToast} />

      {/* Top Navbar */}
      <Navbar
        currentTab={currentTab}
        onTabChange={(tab) => setCurrentTab(tab)}
        darkMode={darkMode}
        onToggleDarkMode={() => setDarkMode(!darkMode)}
        onLogout={() => {
          api.logout();
          setShowAuthModal(true);
        }}
      />

      {/* Main Canvas Area */}
      <main className="relative flex-1 flex flex-col items-center w-full px-4 pt-6 pb-[120px] min-[640px]:px-7">
        {/* Layer 0 canvas glow */}
        <div
          aria-hidden
          className="fixed inset-0 z-0 pointer-events-none bg-[var(--canvas-glow)] bg-no-repeat"
        />
        <div key={currentTab} className="relative z-[1] w-full max-w-[900px] animate-rise">
          {currentTab === 'stream' && (
            <StreamPage
              transactions={transactions}
              monthTransactions={monthTransactions}
              loading={loadingTransactions}
              onEdit={handleEditClick}
              onDelete={(id) => {
                const tx = transactions.find((t) => t.id === id);
                setPendingDelete({
                  id,
                  summary: tx ? `${tx.description} · ${tx.category_name || ''}` : '',
                });
              }}
              onAddRecord={() => {
                setEditingTransaction(null);
                setIsRecordModalOpen(true);
              }}
            />
          )}

          {currentTab === 'stats' && <StatsPage stats={stats} loading={loadingStats} />}

          {currentTab === 'settings' && (
            <SettingsPage
              categories={categories}
              paymentMethods={paymentMethods}
              onAddPaymentMethod={handleAddPaymentMethod}
              onUpdatePaymentMethod={handleUpdatePaymentMethod}
              onDeletePaymentMethod={handleDeletePaymentMethod}
              onAddCategory={handleAddCategory}
              onUpdateCategory={handleUpdateCategory}
              onReorderCategories={handleReorderCategories}
              onDeleteCategory={handleDeleteCategory}
              onAddTag={handleAddTag}
              onUpdateTag={handleUpdateTag}
              onDeleteTag={handleDeleteTag}
              onToast={addToast}
            />
          )}
        </div>
      </main>

      {/* Bottom Floating Controls */}
      <BottomBar
        showFilter={currentTab === 'stream'}
        filter={streamFilter}
        onFilterChange={(f) => setStreamFilter(f)}
        onOpenRecord={() => {
          setEditingTransaction(null);
          setIsRecordModalOpen(true);
        }}
      />

      {/* Record & Edit Modal */}
      <RecordModal
        isOpen={isRecordModalOpen}
        onClose={() => {
          setIsRecordModalOpen(false);
          setEditingTransaction(null);
        }}
        onNavigateToSettings={() => {
          setIsRecordModalOpen(false);
          setEditingTransaction(null);
          setCurrentTab('settings');
        }}
        categories={categories}
        paymentMethods={paymentMethods}
        initialTransaction={editingTransaction}
        onSubmit={handleSaveTransaction}
      />

      {/* Destructive Action Confirmation (in-app dialog) */}
      <ConfirmDialog
        open={pendingDelete !== null}
        title="删除账单"
        description="删除后该笔记录不可恢复。"
        detail={pendingDelete?.summary || undefined}
        confirmLabel="删除"
        tone="danger"
        loading={deleting}
        onConfirm={handleConfirmDelete}
        onCancel={() => setPendingDelete(null)}
      />

      {/* Auth Lock Modal */}
      <AuthModal
        isOpen={showAuthModal}
        onSuccess={() => {
          setShowAuthModal(false);
          setIsAuthenticated(true);
          fetchConfigData();
          if (currentTab === 'stream') fetchTransactions();
          if (currentTab === 'stats') fetchStats();
        }}
      />
    </div>
  );
}
