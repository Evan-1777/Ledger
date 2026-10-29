package server

import (
	"context"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type TagStat struct {
	ID         int64   `json:"id"`
	Name       string  `json:"name"`
	Amount     float64 `json:"amount"`
	Percentage float64 `json:"percentage"`
}

type CategoryStat struct {
	ID         int64     `json:"id"`
	Name       string    `json:"name"`
	Amount     float64   `json:"amount"`
	Percentage float64   `json:"percentage"`
	Tags       []TagStat `json:"tags"`
}

type PaymentMethodStat struct {
	ID         int64   `json:"id"`
	Name       string  `json:"name"`
	Amount     float64 `json:"amount"`
	Percentage float64 `json:"percentage"`
}

type MonthlyTrend struct {
	Month   string  `json:"month"`
	Expense float64 `json:"expense"`
	Income  float64 `json:"income"`
}

type AssetChannelStat struct {
	ID               int64   `json:"id"`
	Name             string  `json:"name"`
	Type             string  `json:"type"`
	RemainingBalance float64 `json:"remaining_balance"`
	InitialBalance   float64 `json:"initial_balance"`
	Percentage       float64 `json:"percentage"`
}

type LiabilityChannelStat struct {
	ID              int64   `json:"id"`
	Name            string  `json:"name"`
	Type            string  `json:"type"`
	CurrentDebt     float64 `json:"current_debt"`
	InitialDebt     float64 `json:"initial_debt"`
	CreditLimit     float64 `json:"credit_limit"`
	RemainingCredit float64 `json:"remaining_credit"`
	UsageRate       float64 `json:"usage_rate"`
}

type AssetSummary struct {
	TotalAssets       float64                `json:"total_assets"`
	TotalLiabilities  float64                `json:"total_liabilities"`
	NetAssets         float64                `json:"net_assets"`
	AssetChannels     []AssetChannelStat     `json:"asset_channels"`
	LiabilityChannels []LiabilityChannelStat `json:"liability_channels"`
}

// statsFilter narrows every stats aggregation to a single category or tag.
// Zero values mean no restriction so the summary endpoint keeps its contract.
type statsFilter struct {
	CategoryID int64
	TagID      int64
}

func (f statsFilter) clause() (string, []any) {
	var query strings.Builder
	args := make([]any, 0, 2)
	if f.CategoryID > 0 {
		query.WriteString(" AND t.category_id = ?")
		args = append(args, f.CategoryID)
	}
	if f.TagID > 0 {
		query.WriteString(" AND t.tag_id = ?")
		args = append(args, f.TagID)
	}
	return query.String(), args
}

type RangeStatsResponse struct {
	Days                       int                 `json:"days"`
	Expense                    float64             `json:"expense"`
	Income                     float64             `json:"income"`
	Balance                    float64             `json:"balance"`
	PreviousExpense            float64             `json:"previous_expense"`
	PreviousIncome             float64             `json:"previous_income"`
	ExpenseCount               int                 `json:"expense_count"`
	IncomeCount                int                 `json:"income_count"`
	CategoryDistribution       []CategoryStat      `json:"category_distribution"`
	IncomeCategoryDistribution []CategoryStat      `json:"income_category_distribution"`
	PaymentDistribution        []PaymentMethodStat `json:"payment_distribution"`
	IncomePaymentDistribution  []PaymentMethodStat `json:"income_payment_distribution"`
	MonthlyTrends              []MonthlyTrend      `json:"monthly_trends"`
}

type StatsSummaryResponse struct {
	WeekExpense                float64             `json:"week_expense"`
	WeekIncome                 float64             `json:"week_income"`
	MonthExpense               float64             `json:"month_expense"`
	MonthIncome                float64             `json:"month_income"`
	LastMonthExpense           float64             `json:"last_month_expense"`
	LastMonthIncome            float64             `json:"last_month_income"`
	MonthBalance               float64             `json:"month_balance"`
	SavingsRate                float64             `json:"savings_rate"`
	CategoryDistribution       []CategoryStat      `json:"category_distribution"`
	IncomeCategoryDistribution []CategoryStat      `json:"income_category_distribution"`
	PaymentDistribution        []PaymentMethodStat `json:"payment_distribution"`
	IncomePaymentDistribution  []PaymentMethodStat `json:"income_payment_distribution"`
	MonthlyTrends              []MonthlyTrend      `json:"monthly_trends"`
	AssetSummary               AssetSummary        `json:"asset_summary"`
}

// nowFunc supplies the current time for stats intervals; tests freeze it.
var nowFunc = time.Now

func (s *Server) handleStatsSummary(w http.ResponseWriter, r *http.Request) {
	loc := time.Local
	now := nowFunc().In(loc)

	// Week interval (Monday to Sunday)
	weekdayOffset := int(now.Weekday() - time.Monday)
	if weekdayOffset < 0 {
		weekdayOffset = 6
	}
	weekStart := time.Date(now.Year(), now.Month(), now.Day()-weekdayOffset, 0, 0, 0, 0, loc)
	weekEnd := weekStart.AddDate(0, 0, 7).Add(-time.Nanosecond)

	// Current month interval
	monthStart := time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, loc)
	monthEnd := monthStart.AddDate(0, 1, 0).Add(-time.Nanosecond)

	// Last month interval
	lastMonthStart := monthStart.AddDate(0, -1, 0)
	lastMonthEnd := monthStart.Add(-time.Nanosecond)

	weekStartUTC := weekStart.UTC().Format(time.RFC3339)
	weekEndUTC := weekEnd.UTC().Format(time.RFC3339)

	monthStartUTC := monthStart.UTC().Format(time.RFC3339)
	monthEndUTC := monthEnd.UTC().Format(time.RFC3339)

	lastMonthStartUTC := lastMonthStart.UTC().Format(time.RFC3339)
	lastMonthEndUTC := lastMonthEnd.UTC().Format(time.RFC3339)

	// 1. Week expense
	weekExpense, err := s.sumByType(r.Context(), "expense", weekStartUTC, weekEndUTC, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query week expense: "+err.Error())
		return
	}

	// 2. Month expense
	monthExpense, err := s.sumByType(r.Context(), "expense", monthStartUTC, monthEndUTC, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query month expense: "+err.Error())
		return
	}

	// 3. Last month expense
	lastMonthExpense, err := s.sumByType(r.Context(), "expense", lastMonthStartUTC, lastMonthEndUTC, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query last month expense: "+err.Error())
		return
	}

	// 4. Income summaries
	weekIncome, err := s.sumByType(r.Context(), "income", weekStartUTC, weekEndUTC, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query week income: "+err.Error())
		return
	}

	monthIncome, err := s.sumByType(r.Context(), "income", monthStartUTC, monthEndUTC, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query month income: "+err.Error())
		return
	}

	lastMonthIncome, err := s.sumByType(r.Context(), "income", lastMonthStartUTC, lastMonthEndUTC, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query last month income: "+err.Error())
		return
	}

	monthBalance := monthIncome - monthExpense
	var savingsRate float64
	if monthIncome > 0 {
		savingsRate = math.Round((monthBalance/monthIncome)*1000) / 10
	}

	// 5. Category and payment distributions (current month)
	catDist, err := s.categoryDistribution(r.Context(), "expense", monthStartUTC, monthEndUTC, monthExpense, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query category distribution: "+err.Error())
		return
	}

	incomeCatDist, err := s.categoryDistribution(r.Context(), "income", monthStartUTC, monthEndUTC, monthIncome, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query income category distribution: "+err.Error())
		return
	}

	// 6. Payment distribution (current month)
	pmDist, err := s.paymentDistribution(r.Context(), "expense", monthStartUTC, monthEndUTC, monthExpense, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query payment distribution: "+err.Error())
		return
	}

	incomePmDist, err := s.paymentDistribution(r.Context(), "income", monthStartUTC, monthEndUTC, monthIncome, statsFilter{})
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query income payment distribution: "+err.Error())
		return
	}

	// 7. Monthly trends (past 6 months)
	monthlyTrends := make([]MonthlyTrend, 0, 6)
	for i := 5; i >= 0; i-- {
		mStart := monthStart.AddDate(0, -i, 0)
		mEnd := mStart.AddDate(0, 1, 0).Add(-time.Nanosecond)
		mStartUTC := mStart.UTC().Format(time.RFC3339)
		mEndUTC := mEnd.UTC().Format(time.RFC3339)

		trendExpense, err := s.sumByType(r.Context(), "expense", mStartUTC, mEndUTC, statsFilter{})
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to query trend expense: "+err.Error())
			return
		}

		trendIncome, err := s.sumByType(r.Context(), "income", mStartUTC, mEndUTC, statsFilter{})
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to query trend income: "+err.Error())
			return
		}

		monthlyTrends = append(monthlyTrends, MonthlyTrend{
			Month:   mStart.Format("2006-01"),
			Expense: trendExpense,
			Income:  trendIncome,
		})
	}

	// 8. Asset and Liability Portfolio Summary
	portfolioRows, err := s.db.QueryContext(r.Context(), `
		SELECT pm.id, pm.name, pm.type, pm.initial_balance_cents, pm.credit_limit_cents,
		       COALESCE(SUM(t.amount_cents), 0) AS tx_sum,
		       COALESCE((SELECT SUM(amount_cents) FROM transactions WHERE source_payment_method_id = pm.id AND type = 'repayment'), 0) AS source_repayment_sum,
		       COALESCE((SELECT SUM(amount_cents + fee_cents) FROM transactions WHERE source_payment_method_id = pm.id AND type = 'transfer'), 0) AS source_transfer_sum
		FROM payment_methods pm
		LEFT JOIN transactions t ON t.payment_method_id = pm.id
		GROUP BY pm.id, pm.name, pm.type, pm.initial_balance_cents, pm.credit_limit_cents
		ORDER BY pm.sort_order ASC, pm.id ASC
	`)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query asset summary: "+err.Error())
		return
	}
	defer portfolioRows.Close()

	type rawAssetItem struct {
		id             int64
		name           string
		chType         string
		initBalCents   int64
		remainingCents int64
	}

	assetItems := make([]rawAssetItem, 0)
	liabilityStats := make([]LiabilityChannelStat, 0)
	var totalAssetsCents int64
	var totalLiabilitiesCents int64

	for portfolioRows.Next() {
		var id int64
		var name, chType string
		var initBalCents, creditLimitCents, txSumCents, sourceRepaymentCents, sourceTransferCents int64
		if err := portfolioRows.Scan(&id, &name, &chType, &initBalCents, &creditLimitCents, &txSumCents, &sourceRepaymentCents, &sourceTransferCents); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to scan asset row: "+err.Error())
			return
		}

		if chType == "liability" {
			currentDebtCents := initBalCents - txSumCents
			totalLiabilitiesCents += currentDebtCents

			var remainingCreditCents int64
			var usageRate float64
			if creditLimitCents > 0 {
				remainingCreditCents = creditLimitCents - currentDebtCents
				if remainingCreditCents > creditLimitCents {
					remainingCreditCents = creditLimitCents
				}
				if remainingCreditCents < 0 {
					remainingCreditCents = 0
				}
				usageRate = math.Round((float64(currentDebtCents)/float64(creditLimitCents))*1000) / 10
				if usageRate < 0 {
					usageRate = 0
				}
			}

			liabilityStats = append(liabilityStats, LiabilityChannelStat{
				ID:              id,
				Name:            name,
				Type:            chType,
				CurrentDebt:     float64(currentDebtCents) / 100.0,
				InitialDebt:     float64(initBalCents) / 100.0,
				CreditLimit:     float64(creditLimitCents) / 100.0,
				RemainingCredit: float64(remainingCreditCents) / 100.0,
				UsageRate:       usageRate,
			})
		} else {
			// Asset channel (default): subtract repayments and transfers funded by this asset channel
			remainingCents := initBalCents + txSumCents - sourceRepaymentCents - sourceTransferCents
			totalAssetsCents += remainingCents
			assetItems = append(assetItems, rawAssetItem{
				id:             id,
				name:           name,
				chType:         chType,
				initBalCents:   initBalCents,
				remainingCents: remainingCents,
			})
		}
	}
	if err := portfolioRows.Err(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "error reading asset rows: "+err.Error())
		return
	}

	assetStats := make([]AssetChannelStat, 0, len(assetItems))
	for _, it := range assetItems {
		var pct float64
		if totalAssetsCents > 0 && it.remainingCents > 0 {
			pct = math.Round((float64(it.remainingCents)/float64(totalAssetsCents))*1000) / 10
		}
		assetStats = append(assetStats, AssetChannelStat{
			ID:               it.id,
			Name:             it.name,
			Type:             it.chType,
			RemainingBalance: float64(it.remainingCents) / 100.0,
			InitialBalance:   float64(it.initBalCents) / 100.0,
			Percentage:       pct,
		})
	}

	netAssetsCents := totalAssetsCents - totalLiabilitiesCents
	assetSummary := AssetSummary{
		TotalAssets:       float64(totalAssetsCents) / 100.0,
		TotalLiabilities:  float64(totalLiabilitiesCents) / 100.0,
		NetAssets:         float64(netAssetsCents) / 100.0,
		AssetChannels:     assetStats,
		LiabilityChannels: liabilityStats,
	}

	resp := StatsSummaryResponse{
		WeekExpense:                weekExpense,
		WeekIncome:                 weekIncome,
		MonthExpense:               monthExpense,
		MonthIncome:                monthIncome,
		LastMonthExpense:           lastMonthExpense,
		LastMonthIncome:            lastMonthIncome,
		MonthBalance:               monthBalance,
		SavingsRate:                savingsRate,
		CategoryDistribution:       catDist,
		IncomeCategoryDistribution: incomeCatDist,
		PaymentDistribution:        pmDist,
		IncomePaymentDistribution:  incomePmDist,
		MonthlyTrends:              monthlyTrends,
		AssetSummary:               assetSummary,
	}

	writeJSON(w, http.StatusOK, resp)
}

func (s *Server) handleStatsRange(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query()
	startRaw := query.Get("start")
	endRaw := query.Get("end")
	if (startRaw == "") != (endRaw == "") {
		writeJSONError(w, http.StatusBadRequest, "start and end must be provided together")
		return
	}

	now := nowFunc().In(time.Local)
	today := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, time.Local)

	var start, end time.Time
	if startRaw == "" {
		start = time.Date(now.Year(), now.Month(), 1, 0, 0, 0, 0, time.Local)
		end = today
	} else {
		var err error
		start, err = time.ParseInLocation("2006-01-02", startRaw, time.Local)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, "invalid start date, expected yyyy-MM-dd")
			return
		}
		end, err = time.ParseInLocation("2006-01-02", endRaw, time.Local)
		if err != nil {
			writeJSONError(w, http.StatusBadRequest, "invalid end date, expected yyyy-MM-dd")
			return
		}
	}
	if start.After(end) {
		writeJSONError(w, http.StatusBadRequest, "start must not be after end")
		return
	}

	categoryID, err := parseOptionalPositiveID(query.Get("category_id"))
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "category_id must be a positive integer")
		return
	}
	tagID, err := parseOptionalPositiveID(query.Get("tag_id"))
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "tag_id must be a positive integer")
		return
	}
	filter := statsFilter{CategoryID: categoryID, TagID: tagID}

	startUTC := start.UTC().Format(time.RFC3339)
	endUTC := end.AddDate(0, 0, 1).Add(-time.Nanosecond).UTC().Format(time.RFC3339)

	expense, err := s.sumByType(r.Context(), "expense", startUTC, endUTC, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query range expense: "+err.Error())
		return
	}
	income, err := s.sumByType(r.Context(), "income", startUTC, endUTC, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query range income: "+err.Error())
		return
	}
	expenseCount, err := s.countByType(r.Context(), "expense", startUTC, endUTC, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to count range expense: "+err.Error())
		return
	}
	incomeCount, err := s.countByType(r.Context(), "income", startUTC, endUTC, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to count range income: "+err.Error())
		return
	}

	previousStart := shiftMonthClamped(start, -1)
	previousEnd := shiftMonthClamped(end, -1)
	previousStartUTC := previousStart.UTC().Format(time.RFC3339)
	previousEndUTC := previousEnd.AddDate(0, 0, 1).Add(-time.Nanosecond).UTC().Format(time.RFC3339)

	previousExpense, err := s.sumByType(r.Context(), "expense", previousStartUTC, previousEndUTC, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query previous expense: "+err.Error())
		return
	}
	previousIncome, err := s.sumByType(r.Context(), "income", previousStartUTC, previousEndUTC, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query previous income: "+err.Error())
		return
	}

	categoryDistribution, err := s.categoryDistribution(r.Context(), "expense", startUTC, endUTC, expense, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query range category distribution: "+err.Error())
		return
	}
	incomeCategoryDistribution, err := s.categoryDistribution(r.Context(), "income", startUTC, endUTC, income, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query range income category distribution: "+err.Error())
		return
	}
	paymentDistribution, err := s.paymentDistribution(r.Context(), "expense", startUTC, endUTC, expense, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query range payment distribution: "+err.Error())
		return
	}
	incomePaymentDistribution, err := s.paymentDistribution(r.Context(), "income", startUTC, endUTC, income, filter)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query range income payment distribution: "+err.Error())
		return
	}

	monthStart := time.Date(end.Year(), end.Month(), 1, 0, 0, 0, 0, time.Local)
	monthlyTrends := make([]MonthlyTrend, 0, 6)
	for i := 5; i >= 0; i-- {
		mStart := monthStart.AddDate(0, -i, 0)
		mEnd := mStart.AddDate(0, 1, 0).Add(-time.Nanosecond)
		mStartUTC := mStart.UTC().Format(time.RFC3339)
		mEndUTC := mEnd.UTC().Format(time.RFC3339)
		trendExpense, err := s.sumByType(r.Context(), "expense", mStartUTC, mEndUTC, filter)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to query range trend expense: "+err.Error())
			return
		}
		trendIncome, err := s.sumByType(r.Context(), "income", mStartUTC, mEndUTC, filter)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to query range trend income: "+err.Error())
			return
		}
		monthlyTrends = append(monthlyTrends, MonthlyTrend{
			Month:   mStart.Format("2006-01"),
			Expense: trendExpense,
			Income:  trendIncome,
		})
	}

	writeJSON(w, http.StatusOK, RangeStatsResponse{
		Days:                       rangeDays(start, end, today),
		Expense:                    expense,
		Income:                     income,
		Balance:                    income - expense,
		PreviousExpense:            previousExpense,
		PreviousIncome:             previousIncome,
		ExpenseCount:               expenseCount,
		IncomeCount:                incomeCount,
		CategoryDistribution:       categoryDistribution,
		IncomeCategoryDistribution: incomeCategoryDistribution,
		PaymentDistribution:        paymentDistribution,
		IncomePaymentDistribution:  incomePaymentDistribution,
		MonthlyTrends:              monthlyTrends,
	})
}

func parseOptionalPositiveID(raw string) (int64, error) {
	if raw == "" {
		return 0, nil
	}
	id, err := strconv.ParseInt(raw, 10, 64)
	if err != nil || id <= 0 {
		return 0, fmt.Errorf("invalid positive id %q", raw)
	}
	return id, nil
}

func rangeDays(start, end, today time.Time) int {
	if start.After(today) {
		return 1
	}
	last := end
	if today.Before(end) {
		last = today
	}
	a := time.Date(start.Year(), start.Month(), start.Day(), 0, 0, 0, 0, time.UTC)
	b := time.Date(last.Year(), last.Month(), last.Day(), 0, 0, 0, 0, time.UTC)
	return int(b.Sub(a).Hours()/24) + 1
}

func shiftMonthClamped(date time.Time, months int) time.Time {
	first := time.Date(date.Year(), date.Month()+time.Month(months), 1, 0, 0, 0, 0, date.Location())
	lastDay := first.AddDate(0, 1, -1).Day()
	day := date.Day()
	if day > lastDay {
		day = lastDay
	}
	return time.Date(first.Year(), first.Month(), day, 0, 0, 0, 0, date.Location())
}

func (s *Server) sumByType(ctx context.Context, txType, startUTC, endUTC string, filter statsFilter) (float64, error) {
	var cents int64
	filterSQL, filterArgs := filter.clause()
	args := append([]any{startUTC, endUTC, txType}, filterArgs...)
	err := s.db.QueryRowContext(ctx, `
		SELECT COALESCE(SUM(t.amount_cents), 0)
		FROM transactions t
		JOIN categories c ON c.id = t.category_id
		WHERE t.transacted_at >= ? AND t.transacted_at <= ? AND t.type = ? AND c.exclude_from_stats = 0`+filterSQL+`
	`, args...).Scan(&cents)
	if err != nil {
		return 0, err
	}
	return math.Abs(float64(cents)) / 100.0, nil
}

func (s *Server) countByType(ctx context.Context, txType, startUTC, endUTC string, filter statsFilter) (int, error) {
	var count int
	filterSQL, filterArgs := filter.clause()
	args := append([]any{startUTC, endUTC, txType}, filterArgs...)
	err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*)
		FROM transactions t
		JOIN categories c ON c.id = t.category_id
		WHERE t.transacted_at >= ? AND t.transacted_at <= ? AND t.type = ? AND c.exclude_from_stats = 0`+filterSQL+`
	`, args...).Scan(&count)
	if err != nil {
		return 0, err
	}
	return count, nil
}

func (s *Server) categoryDistribution(ctx context.Context, txType, startUTC, endUTC string, total float64, filter statsFilter) ([]CategoryStat, error) {
	dist := make([]CategoryStat, 0)
	index := make(map[int64]int)
	filterSQL, filterArgs := filter.clause()

	args := append([]any{startUTC, endUTC, txType}, filterArgs...)
	rows, err := s.db.QueryContext(ctx, `
		SELECT c.id, c.name, COALESCE(SUM(t.amount_cents), 0)
		FROM categories c
		JOIN transactions t ON t.category_id = c.id
		WHERE t.transacted_at >= ? AND t.transacted_at <= ? AND t.type = ? AND c.exclude_from_stats = 0`+filterSQL+`
		GROUP BY c.id, c.name
		ORDER BY ABS(SUM(t.amount_cents)) DESC
	`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var catID int64
		var catName string
		var catCents int64
		if err := rows.Scan(&catID, &catName, &catCents); err != nil {
			return nil, err
		}
		amt := math.Abs(float64(catCents)) / 100.0
		var pct float64
		if total > 0 {
			pct = math.Round((amt/total)*1000) / 10
		}
		index[catID] = len(dist)
		dist = append(dist, CategoryStat{
			ID:         catID,
			Name:       catName,
			Amount:     amt,
			Percentage: pct,
			Tags:       make([]TagStat, 0),
		})
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	tagArgs := append([]any{startUTC, endUTC, txType}, filterArgs...)
	tagRows, err := s.db.QueryContext(ctx, `
		SELECT t.category_id, tg.id, tg.name, COALESCE(SUM(t.amount_cents), 0)
		FROM tags tg
		JOIN transactions t ON t.tag_id = tg.id
		JOIN categories c ON c.id = t.category_id
		WHERE t.transacted_at >= ? AND t.transacted_at <= ? AND t.type = ? AND c.exclude_from_stats = 0`+filterSQL+`
		GROUP BY t.category_id, tg.id, tg.name
		ORDER BY ABS(SUM(t.amount_cents)) DESC
	`, tagArgs...)
	if err != nil {
		return nil, err
	}
	defer tagRows.Close()

	for tagRows.Next() {
		var catID, tagID int64
		var tagName string
		var tagCents int64
		if err := tagRows.Scan(&catID, &tagID, &tagName, &tagCents); err != nil {
			return nil, err
		}
		if idx, ok := index[catID]; ok {
			amt := math.Abs(float64(tagCents)) / 100.0
			var pct float64
			if dist[idx].Amount > 0 {
				pct = math.Round((amt/dist[idx].Amount)*1000) / 10
			}
			dist[idx].Tags = append(dist[idx].Tags, TagStat{
				ID:         tagID,
				Name:       tagName,
				Amount:     amt,
				Percentage: pct,
			})
		}
	}

	return dist, tagRows.Err()
}

func (s *Server) paymentDistribution(ctx context.Context, txType, startUTC, endUTC string, total float64, filter statsFilter) ([]PaymentMethodStat, error) {
	dist := make([]PaymentMethodStat, 0)
	filterSQL, filterArgs := filter.clause()
	args := append([]any{startUTC, endUTC, txType}, filterArgs...)

	rows, err := s.db.QueryContext(ctx, `
		SELECT pm.id, pm.name, COALESCE(SUM(t.amount_cents), 0)
		FROM payment_methods pm
		JOIN transactions t ON t.payment_method_id = pm.id
		JOIN categories c ON c.id = t.category_id
		WHERE t.transacted_at >= ? AND t.transacted_at <= ? AND t.type = ? AND c.exclude_from_stats = 0`+filterSQL+`
		GROUP BY pm.id, pm.name
		ORDER BY ABS(SUM(t.amount_cents)) DESC
	`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var pmID int64
		var pmName string
		var pmCents int64
		if err := rows.Scan(&pmID, &pmName, &pmCents); err != nil {
			return nil, err
		}
		amt := math.Abs(float64(pmCents)) / 100.0
		var pct float64
		if total > 0 {
			pct = math.Round((amt/total)*1000) / 10
		}
		dist = append(dist, PaymentMethodStat{
			ID:         pmID,
			Name:       pmName,
			Amount:     amt,
			Percentage: pct,
		})
	}

	return dist, rows.Err()
}
