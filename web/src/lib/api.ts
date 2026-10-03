export interface PaymentMethod {
  id: number;
  name: string;
  sort_order: number;
  type: 'asset' | 'liability';
  initial_balance: number;
  credit_limit: number;
  created_at: string;
}

export interface Tag {
  id: number;
  category_id: number;
  name: string;
  sort_order: number;
  created_at: string;
}

export interface Category {
  id: number;
  name: string;
  sort_order: number;
  created_at: string;
  tags: Tag[];
}

export interface Transaction {
  id: number;
  amount_cents: number;
  amount: number;
  description: string;
  payment_method_id: number;
  payment_method_name: string;
  category_id: number;
  category_name: string;
  tag_id: number;
  tag_name: string;
  transacted_at: string;
  created_at: string;
}

export interface TagStat {
  id: number;
  name: string;
  amount: number;
  percentage: number;
}

export interface CategoryStat {
  id: number;
  name: string;
  amount: number;
  percentage: number;
  tags: TagStat[];
}

export interface PaymentMethodStat {
  id: number;
  name: string;
  amount: number;
  percentage: number;
}

export interface MonthlyTrend {
  month: string;
  expense: number;
  income: number;
}

export interface AssetChannelStat {
  id: number;
  name: string;
  type: string;
  remaining_balance: number;
  initial_balance: number;
  percentage: number;
}

export interface LiabilityChannelStat {
  id: number;
  name: string;
  type: string;
  current_debt: number;
  initial_debt: number;
  credit_limit: number;
  remaining_credit: number;
  usage_rate: number;
}

export interface AssetSummary {
  total_assets: number;
  total_liabilities: number;
  net_assets: number;
  asset_channels: AssetChannelStat[];
  liability_channels: LiabilityChannelStat[];
}

export interface StatsSummary {
  week_expense: number;
  month_expense: number;
  last_month_expense: number;
  month_income: number;
  month_balance: number;
  savings_rate: number;
  category_distribution: CategoryStat[];
  payment_distribution: PaymentMethodStat[];
  monthly_trends: MonthlyTrend[];
  asset_summary: AssetSummary;
}

type AuthCallback = (authenticated: boolean) => void;
let authListener: AuthCallback | null = null;

export function onAuthStateChange(listener: AuthCallback) {
  authListener = listener;
}

function notifyAuthState(authenticated: boolean) {
  if (authListener) {
    authListener(authenticated);
  }
}

export function getToken(): string | null {
  return localStorage.getItem('ledger_token');
}

export function setToken(token: string) {
  localStorage.setItem('ledger_token', token);
  notifyAuthState(true);
}

export function removeToken() {
  localStorage.removeItem('ledger_token');
  notifyAuthState(false);
}

async function request<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
  const token = getToken();
  const headers = new Headers(options.headers || {});
  headers.set('Content-Type', 'application/json');
  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(endpoint, {
    ...options,
    headers,
  });

  if (response.status === 401) {
    notifyAuthState(false);
    throw new Error('未授权或登录已过期，请输入管理员密码');
  }

  const data = await response.json().catch(() => null);

  if (!response.ok) {
    const errorMsg = data?.error || `请求失败 (${response.status})`;
    throw new Error(errorMsg);
  }

  return data as T;
}

export const api = {
  async login(password: string): Promise<{ token: string; expires_at: number }> {
    const res = await request<{ token: string; expires_at: number }>('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({ password }),
    });
    setToken(res.token);
    return res;
  },

  async checkAuth(): Promise<boolean> {
    try {
      await request<{ status: string }>('/api/auth/check');
      notifyAuthState(true);
      return true;
    } catch {
      notifyAuthState(false);
      return false;
    }
  },

  logout() {
    removeToken();
  },

  // Payment Methods
  getPaymentMethods(): Promise<PaymentMethod[]> {
    return request<PaymentMethod[]>('/api/payment-methods');
  },

  createPaymentMethod(
    name: string,
    sort_order: number,
    type: 'asset' | 'liability' = 'asset',
    initial_balance: number = 0,
    credit_limit: number = 0
  ): Promise<PaymentMethod> {
    return request<PaymentMethod>('/api/payment-methods', {
      method: 'POST',
      body: JSON.stringify({ name, sort_order, type, initial_balance, credit_limit }),
    });
  },

  updatePaymentMethod(
    id: number,
    name: string,
    sort_order: number,
    type?: 'asset' | 'liability',
    initial_balance?: number,
    credit_limit?: number
  ): Promise<PaymentMethod> {
    return request<PaymentMethod>(`/api/payment-methods/${id}`, {
      method: 'PUT',
      body: JSON.stringify({ name, sort_order, type, initial_balance, credit_limit }),
    });
  },

  deletePaymentMethod(id: number): Promise<{ success: boolean }> {
    return request<{ success: boolean }>(`/api/payment-methods/${id}`, {
      method: 'DELETE',
    });
  },

  // Categories
  getCategories(): Promise<Category[]> {
    return request<Category[]>('/api/categories');
  },

  createCategory(name: string, sort_order: number): Promise<Category> {
    return request<Category>('/api/categories', {
      method: 'POST',
      body: JSON.stringify({ name, sort_order }),
    });
  },

  updateCategory(id: number, name: string, sort_order: number): Promise<Category> {
    return request<Category>(`/api/categories/${id}`, {
      method: 'PUT',
      body: JSON.stringify({ name, sort_order }),
    });
  },

  deleteCategory(id: number): Promise<{ success: boolean }> {
    return request<{ success: boolean }>(`/api/categories/${id}`, {
      method: 'DELETE',
    });
  },

  // Tags
  getTags(categoryId?: number): Promise<Tag[]> {
    const query = categoryId ? `?category_id=${categoryId}` : '';
    return request<Tag[]>(`/api/tags${query}`);
  },

  createTag(categoryId: number, name: string, sort_order: number): Promise<Tag> {
    return request<Tag>('/api/tags', {
      method: 'POST',
      body: JSON.stringify({ category_id: categoryId, name, sort_order }),
    });
  },

  updateTag(id: number, name: string, sort_order: number): Promise<Tag> {
    return request<Tag>(`/api/tags/${id}`, {
      method: 'PUT',
      body: JSON.stringify({ name, sort_order }),
    });
  },

  deleteTag(id: number): Promise<{ success: boolean }> {
    return request<{ success: boolean }>(`/api/tags/${id}`, {
      method: 'DELETE',
    });
  },

  // Transactions
  getTransactions(type?: 'all' | 'expense' | 'income', limit = 100): Promise<Transaction[]> {
    const params = new URLSearchParams();
    if (type && type !== 'all') {
      params.set('type', type);
    }
    params.set('limit', String(limit));
    return request<Transaction[]>(`/api/transactions?${params.toString()}`);
  },

  createTransaction(data: {
    amount: number;
    description: string;
    payment_method_id: number;
    category_id: number;
    tag_id: number;
    transacted_at?: string;
  }): Promise<Transaction> {
    return request<Transaction>('/api/transactions', {
      method: 'POST',
      body: JSON.stringify(data),
    });
  },

  updateTransaction(
    id: number,
    data: {
      amount: number;
      description: string;
      payment_method_id: number;
      category_id: number;
      tag_id: number;
      transacted_at?: string;
    }
  ): Promise<Transaction> {
    return request<Transaction>(`/api/transactions/${id}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    });
  },

  deleteTransaction(id: number): Promise<{ success: boolean }> {
    return request<{ success: boolean }>(`/api/transactions/${id}`, {
      method: 'DELETE',
    });
  },

  // Stats
  getStatsSummary(): Promise<StatsSummary> {
    return request<StatsSummary>('/api/stats/summary');
  },
};
