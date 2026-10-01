package server

import (
	"math"
	"net/http"
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

type StatsSummaryResponse struct {
	WeekExpense          float64             `json:"week_expense"`
	MonthExpense         float64             `json:"month_expense"`
	LastMonthExpense     float64             `json:"last_month_expense"`
	MonthIncome          float64             `json:"month_income"`
	MonthBalance         float64             `json:"month_balance"`
	SavingsRate          float64             `json:"savings_rate"`
	CategoryDistribution []CategoryStat      `json:"category_distribution"`
	PaymentDistribution  []PaymentMethodStat `json:"payment_distribution"`
	MonthlyTrends        []MonthlyTrend      `json:"monthly_trends"`
}

func (s *Server) handleStatsSummary(w http.ResponseWriter, r *http.Request) {
	loc := time.Local
	now := time.Now().In(loc)

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
	var weekExpenseCents int64
	if err := s.db.QueryRowContext(r.Context(),
		"SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE transacted_at >= ? AND transacted_at <= ? AND amount_cents < 0",
		weekStartUTC, weekEndUTC,
	).Scan(&weekExpenseCents); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query week expense: "+err.Error())
		return
	}
	weekExpense := math.Abs(float64(weekExpenseCents)) / 100.0

	// 2. Month expense
	var monthExpenseCents int64
	if err := s.db.QueryRowContext(r.Context(),
		"SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE transacted_at >= ? AND transacted_at <= ? AND amount_cents < 0",
		monthStartUTC, monthEndUTC,
	).Scan(&monthExpenseCents); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query month expense: "+err.Error())
		return
	}
	monthExpense := math.Abs(float64(monthExpenseCents)) / 100.0

	// 3. Last month expense
	var lastMonthExpenseCents int64
	if err := s.db.QueryRowContext(r.Context(),
		"SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE transacted_at >= ? AND transacted_at <= ? AND amount_cents < 0",
		lastMonthStartUTC, lastMonthEndUTC,
	).Scan(&lastMonthExpenseCents); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query last month expense: "+err.Error())
		return
	}
	lastMonthExpense := math.Abs(float64(lastMonthExpenseCents)) / 100.0

	// 4. Month income
	var monthIncomeCents int64
	if err := s.db.QueryRowContext(r.Context(),
		"SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE transacted_at >= ? AND transacted_at <= ? AND amount_cents > 0",
		monthStartUTC, monthEndUTC,
	).Scan(&monthIncomeCents); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query month income: "+err.Error())
		return
	}
	monthIncome := float64(monthIncomeCents) / 100.0

	monthBalance := monthIncome - monthExpense
	var savingsRate float64
	if monthIncome > 0 {
		savingsRate = math.Round((monthBalance/monthIncome)*1000) / 10
	}

	// 5. Category distribution (current month)
	catDist := make([]CategoryStat, 0)
	catIndex := make(map[int64]int)

	catRows, err := s.db.QueryContext(r.Context(), `
		SELECT c.id, c.name, COALESCE(SUM(t.amount_cents), 0)
		FROM categories c
		JOIN transactions t ON t.category_id = c.id
		WHERE t.transacted_at >= ? AND t.transacted_at <= ? AND t.amount_cents < 0
		GROUP BY c.id, c.name
		ORDER BY SUM(t.amount_cents) ASC
	`, monthStartUTC, monthEndUTC)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query category distribution: "+err.Error())
		return
	}
	defer catRows.Close()

	for catRows.Next() {
		var catID int64
		var catName string
		var catCents int64
		if err := catRows.Scan(&catID, &catName, &catCents); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to scan category distribution: "+err.Error())
			return
		}
		amt := math.Abs(float64(catCents)) / 100.0
		var pct float64
		if monthExpense > 0 {
			pct = math.Round((amt/monthExpense)*1000) / 10
		}
		catIndex[catID] = len(catDist)
		catDist = append(catDist, CategoryStat{
			ID:         catID,
			Name:       catName,
			Amount:     amt,
			Percentage: pct,
			Tags:       make([]TagStat, 0),
		})
	}
	if err := catRows.Err(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "error reading category distribution: "+err.Error())
		return
	}

	// Sub-tag drill-down
	tagRows, err := s.db.QueryContext(r.Context(), `
		SELECT t.category_id, tg.id, tg.name, COALESCE(SUM(t.amount_cents), 0)
		FROM tags tg
		JOIN transactions t ON t.tag_id = tg.id
		WHERE t.transacted_at >= ? AND t.transacted_at <= ? AND t.amount_cents < 0
		GROUP BY t.category_id, tg.id, tg.name
		ORDER BY SUM(t.amount_cents) ASC
	`, monthStartUTC, monthEndUTC)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query tag distribution: "+err.Error())
		return
	}
	defer tagRows.Close()

	for tagRows.Next() {
		var catID, tagID int64
		var tagName string
		var tagCents int64
		if err := tagRows.Scan(&catID, &tagID, &tagName, &tagCents); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to scan tag distribution: "+err.Error())
			return
		}
		if idx, ok := catIndex[catID]; ok {
			amt := math.Abs(float64(tagCents)) / 100.0
			var pct float64
			if catDist[idx].Amount > 0 {
				pct = math.Round((amt/catDist[idx].Amount)*1000) / 10
			}
			catDist[idx].Tags = append(catDist[idx].Tags, TagStat{
				ID:         tagID,
				Name:       tagName,
				Amount:     amt,
				Percentage: pct,
			})
		}
	}
	if err := tagRows.Err(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "error reading tag distribution: "+err.Error())
		return
	}

	// 6. Payment distribution (current month)
	pmDist := make([]PaymentMethodStat, 0)
	pmRows, err := s.db.QueryContext(r.Context(), `
		SELECT pm.id, pm.name, COALESCE(SUM(t.amount_cents), 0)
		FROM payment_methods pm
		JOIN transactions t ON t.payment_method_id = pm.id
		WHERE t.transacted_at >= ? AND t.transacted_at <= ? AND t.amount_cents < 0
		GROUP BY pm.id, pm.name
		ORDER BY SUM(t.amount_cents) ASC
	`, monthStartUTC, monthEndUTC)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to query payment distribution: "+err.Error())
		return
	}
	defer pmRows.Close()

	for pmRows.Next() {
		var pmID int64
		var pmName string
		var pmCents int64
		if err := pmRows.Scan(&pmID, &pmName, &pmCents); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to scan payment distribution: "+err.Error())
			return
		}
		amt := math.Abs(float64(pmCents)) / 100.0
		var pct float64
		if monthExpense > 0 {
			pct = math.Round((amt/monthExpense)*1000) / 10
		}
		pmDist = append(pmDist, PaymentMethodStat{
			ID:         pmID,
			Name:       pmName,
			Amount:     amt,
			Percentage: pct,
		})
	}
	if err := pmRows.Err(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, "error reading payment distribution: "+err.Error())
		return
	}

	// 7. Monthly trends (past 6 months)
	monthlyTrends := make([]MonthlyTrend, 0, 6)
	for i := 5; i >= 0; i-- {
		mStart := monthStart.AddDate(0, -i, 0)
		mEnd := mStart.AddDate(0, 1, 0).Add(-time.Nanosecond)
		mStartUTC := mStart.UTC().Format(time.RFC3339)
		mEndUTC := mEnd.UTC().Format(time.RFC3339)

		var expCents, incCents int64
		if err := s.db.QueryRowContext(r.Context(),
			"SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE transacted_at >= ? AND transacted_at <= ? AND amount_cents < 0",
			mStartUTC, mEndUTC,
		).Scan(&expCents); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to query trend expense: "+err.Error())
			return
		}

		if err := s.db.QueryRowContext(r.Context(),
			"SELECT COALESCE(SUM(amount_cents), 0) FROM transactions WHERE transacted_at >= ? AND transacted_at <= ? AND amount_cents > 0",
			mStartUTC, mEndUTC,
		).Scan(&incCents); err != nil {
			writeJSONError(w, http.StatusInternalServerError, "failed to query trend income: "+err.Error())
			return
		}

		monthlyTrends = append(monthlyTrends, MonthlyTrend{
			Month:   mStart.Format("2006-01"),
			Expense: math.Abs(float64(expCents)) / 100.0,
			Income:  float64(incCents) / 100.0,
		})
	}

	resp := StatsSummaryResponse{
		WeekExpense:          weekExpense,
		MonthExpense:         monthExpense,
		LastMonthExpense:     lastMonthExpense,
		MonthIncome:          monthIncome,
		MonthBalance:         monthBalance,
		SavingsRate:          savingsRate,
		CategoryDistribution: catDist,
		PaymentDistribution:  pmDist,
		MonthlyTrends:        monthlyTrends,
	}

	writeJSON(w, http.StatusOK, resp)
}
