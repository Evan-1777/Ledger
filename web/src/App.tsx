import { useState, useEffect, useCallback } from 'react';
import { Navbar, TabType } from './components/Navbar';
import { BottomBar, FilterType } from './components/BottomBar';
import { AuthModal } from './components/AuthModal';
import { RecordModal } from './components/RecordModal';
import { Toast, ToastMessage } from './components/Toast';
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
  const [stats, setStats] = useState<StatsSummary | null>(null);

  // Loading states
  const [loadingTransactions, setLoadingTransactions] = useState(false);
  const [loadingStats, setLoadingStats] = useState(false);

  // Modals & Toasts
  const [isRecordModalOpen, setIsRecordModalOpen] = useState(false);
  const [editingTransaction, setEditingTransaction] = useState<Transaction | null>(null);
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

  // Sync theme
  useEffect(() => {
    if (darkMode) {
      document.body.classList.add('dark-mode');
      localStorage.setItem('ledger_theme', 'dark');
    } else {
      document.body.classList.remove('dark-mode');
      localStorage.setItem('ledger_theme', 'light');
    }
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
      const data = await api.getTransactions(streamFilter);
      setTransactions(data);
    } catch (err: any) {
      if (isAuthenticated) {
        addToast('error', err?.message || '获取流水失败');
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
    } catch (err: any) {
      if (isAuthenticated) {
        addToast('error', err?.message || '获取统计失败');
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

  const handleDeleteTransaction = async (id: number) => {
    if (!window.confirm('确认删除此笔账单？')) return;
    try {
      await api.deleteTransaction(id);
      addToast('success', '账单已删除');
      fetchTransactions();
      if (currentTab === 'stats') fetchStats();
    } catch (err: any) {
      addToast('error', err?.message || '删除失败');
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
    } catch (err: any) {
      addToast('error', err?.message || '添加失败');
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
    } catch (err: any) {
      addToast('error', err?.message || '更新失败');
      throw err;
    }
  };

  const handleDeletePaymentMethod = async (id: number) => {
    try {
      await api.deletePaymentMethod(id);
      addToast('success', '渠道已删除');
      fetchConfigData();
    } catch (err: any) {
      addToast('error', err?.message || '删除失败');
    }
  };

  const handleAddCategory = async (name: string, type: 'expense' | 'income' = 'expense') => {
    try {
      await api.createCategory(name, categories.length + 1, type);
      addToast('success', `${type === 'income' ? '收入分类' : '消费类型'}「${name}」已创建`);
      fetchConfigData();
    } catch (err: any) {
      addToast('error', err?.message || '创建失败');
    }
  };

  const handleDeleteCategory = async (id: number) => {
    try {
      await api.deleteCategory(id);
      addToast('success', '消费类型已删除');
      fetchConfigData();
    } catch (err: any) {
      addToast('error', err?.message || '删除失败');
    }
  };

  const handleUpdateCategory = async (id: number, name: string, sort_order: number, type?: 'expense' | 'income') => {
    try {
      await api.updateCategory(id, name, sort_order, type);
      fetchConfigData();
    } catch (err: any) {
      const msg = err?.message?.includes('category already exists')
        ? '分类名称已存在'
        : err?.message || '更新分类失败';
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
    } catch (err: any) {
      addToast('error', err?.message || '调整分类顺序失败');
      await fetchConfigData();
      throw err;
    }
  };

  const handleAddTag = async (categoryId: number, name: string) => {
    try {
      await api.createTag(categoryId, name, 0);
      addToast('success', `细分标签「${name}」已添加`);
      fetchConfigData();
    } catch (err: any) {
      addToast('error', err?.message || '添加失败');
    }
  };

  const handleUpdateTag = async (id: number, name: string, sort_order: number) => {
    try {
      await api.updateTag(id, name, sort_order);
      fetchConfigData();
    } catch (err: any) {
      const msg = err?.message?.includes('tag already exists')
        ? '该分类下已存在同名标签'
        : err?.message || '更新细分标签失败';
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
    } catch (err: any) {
      addToast('error', err?.message || '删除失败');
    }
  };

  return (
    <div className="min-h-screen flex flex-col bg-[var(--color-canvas-bg)] [background-image:var(--canvas-gradient)] bg-no-repeat text-[var(--color-neutral-fg-1)] transition-colors duration-200">
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
      <main className="flex-1 flex flex-col items-center px-5 pt-6 pb-28 w-full">
        {currentTab === 'stream' && (
          <StreamPage
            transactions={transactions}
            loading={loadingTransactions}
            onEdit={handleEditClick}
            onDelete={handleDeleteTransaction}
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
