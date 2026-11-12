package server

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"
)

type Transaction struct {
	ID                      int64   `json:"id"`
	Type                    string  `json:"type"`
	AmountCents             int64   `json:"amount_cents"`
	Amount                  float64 `json:"amount"`
	FeeCents                int64   `json:"fee_cents"`
	Fee                     float64 `json:"fee"`
	Description             string  `json:"description"`
	PaymentMethodID         int64   `json:"payment_method_id"`
	PaymentMethodName       string  `json:"payment_method_name"`
	SourcePaymentMethodID   *int64  `json:"source_payment_method_id,omitempty"`
	SourcePaymentMethodName string  `json:"source_payment_method_name,omitempty"`
	CategoryID              int64   `json:"category_id"`
	CategoryName            string  `json:"category_name"`
	TagID                   int64   `json:"tag_id"`
	TagName                 string  `json:"tag_name"`
	TransactedAt            string  `json:"transacted_at"`
	CreatedAt               string  `json:"created_at"`
	RefundedAt              *string `json:"refunded_at,omitempty"`
}

type TransactionRequest struct {
	Type                  string  `json:"type"`
	Amount                float64 `json:"amount"`
	Fee                   float64 `json:"fee"`
	Description           string  `json:"description"`
	PaymentMethodID       int64   `json:"payment_method_id"`
	SourcePaymentMethodID *int64  `json:"source_payment_method_id"`
	CategoryID            int64   `json:"category_id"`
	TagID                 int64   `json:"tag_id"`
	TransactedAt          string  `json:"transacted_at"`
}

func (s *Server) handleListTransactions(w http.ResponseWriter, r *http.Request) {
	limit := 100
	offset := 0

	if lStr := r.URL.Query().Get("limit"); lStr != "" {
		if l, err := strconv.Atoi(lStr); err == nil && l > 0 {
			if l > 500 {
				limit = 500
			} else {
				limit = l
			}
		}
	}

	if oStr := r.URL.Query().Get("offset"); oStr != "" {
		if o, err := strconv.Atoi(oStr); err == nil && o >= 0 {
			offset = o
		}
	}

	conditions := make([]string, 0, 5)
	args := make([]any, 0, 8)

	// 未知 type 保持既有「不过滤」语义
	typeFilter := strings.ToLower(r.URL.Query().Get("type"))
	if typeFilter == "expense" || typeFilter == "income" || typeFilter == "repayment" || typeFilter == "transfer" {
		conditions = append(conditions, "t.type = ?")
		args = append(args, typeFilter)
	}

	categoryID, err := parseOptionalPositiveID(r.URL.Query().Get("category_id"))
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "category_id must be a positive integer")
		return
	}
	if categoryID > 0 {
		conditions = append(conditions, "t.category_id = ?")
		args = append(args, categoryID)
	}

	tagID, err := parseOptionalPositiveID(r.URL.Query().Get("tag_id"))
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "tag_id must be a positive integer")
		return
	}
	if tagID > 0 {
		conditions = append(conditions, "t.tag_id = ?")
		args = append(args, tagID)
	}

	channelID, err := parseOptionalPositiveID(r.URL.Query().Get("payment_method_id"))
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "payment_method_id must be a positive integer")
		return
	}
	if channelID > 0 {
		// 转账的转出账户与还款的来源账户也参与匹配，与渠道引用检查同口径
		conditions = append(conditions, "(t.payment_method_id = ? OR t.source_payment_method_id = ?)")
		args = append(args, channelID, channelID)
	}

	if keyword := strings.TrimSpace(r.URL.Query().Get("q")); keyword != "" {
		pattern := "%" + escapeLike(keyword) + "%"
		conditions = append(conditions, `(t.description LIKE ? ESCAPE '\' OR c.name LIKE ? ESCAPE '\' OR tg.name LIKE ? ESCAPE '\' OR pm.name LIKE ? ESCAPE '\' OR spm.name LIKE ? ESCAPE '\')`)
		args = append(args, pattern, pattern, pattern, pattern, pattern)
	}

	var query strings.Builder
	query.WriteString(`
		SELECT t.id, t.type, t.amount_cents, t.fee_cents, t.description,
		       t.payment_method_id, COALESCE(pm.name, ''),
		       t.source_payment_method_id, COALESCE(spm.name, ''),
		       t.category_id, COALESCE(c.name, ''),
		       t.tag_id, COALESCE(tg.name, ''),
		       t.transacted_at, t.created_at, t.refunded_at
		FROM transactions t
		LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
		LEFT JOIN payment_methods spm ON t.source_payment_method_id = spm.id
		LEFT JOIN categories c ON t.category_id = c.id
		LEFT JOIN tags tg ON t.tag_id = tg.id
	`)

	if len(conditions) > 0 {
		query.WriteString(" WHERE ")
		query.WriteString(strings.Join(conditions, " AND "))
	}

	query.WriteString(" ORDER BY t.transacted_at DESC, t.id DESC LIMIT ? OFFSET ?")
	args = append(args, limit, offset)

	rows, err := s.db.QueryContext(r.Context(), query.String(), args...)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	list := make([]Transaction, 0)
	for rows.Next() {
		var item Transaction
		var srcPMID sql.NullInt64
		var srcPMName sql.NullString
		var refundedAt sql.NullString
		err := rows.Scan(
			&item.ID, &item.Type, &item.AmountCents, &item.FeeCents, &item.Description,
			&item.PaymentMethodID, &item.PaymentMethodName,
			&srcPMID, &srcPMName,
			&item.CategoryID, &item.CategoryName,
			&item.TagID, &item.TagName,
			&item.TransactedAt, &item.CreatedAt, &refundedAt,
		)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
			return
		}
		if srcPMID.Valid {
			val := srcPMID.Int64
			item.SourcePaymentMethodID = &val
		}
		if srcPMName.Valid {
			item.SourcePaymentMethodName = srcPMName.String
		}
		if refundedAt.Valid {
			val := refundedAt.String
			item.RefundedAt = &val
		}
		item.Amount = float64(item.AmountCents) / 100.0
		item.Fee = float64(item.FeeCents) / 100.0
		list = append(list, item)
	}

	writeJSON(w, http.StatusOK, list)
}

// escapeLike 转义 LIKE 模式中的通配符，使关键词按字面量匹配。
func escapeLike(raw string) string {
	return strings.NewReplacer(`\`, `\\`, "%", `\%`, "_", `\_`).Replace(raw)
}
func (s *Server) handleCreateTransaction(w http.ResponseWriter, r *http.Request) {
	var req TransactionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	amountCents, feeCents, txType, transactedAt, err := s.validateTransactionInput(r, &req)
	if err != nil {
		var brErr *badRequestError
		if errors.As(err, &brErr) {
			writeJSONError(w, http.StatusBadRequest, brErr.Error())
		} else {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
		}
		return
	}

	res, err := s.db.ExecContext(
		r.Context(),
		`INSERT INTO transactions (amount_cents, fee_cents, description, payment_method_id, source_payment_method_id, category_id, tag_id, transacted_at, type)
		 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		amountCents, feeCents, req.Description, req.PaymentMethodID, req.SourcePaymentMethodID, req.CategoryID, req.TagID, transactedAt, txType,
	)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to insert transaction: "+err.Error())
		return
	}

	id, _ := res.LastInsertId()
	txItem, err := s.getTransactionByID(r, id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, txItem)
}

func (s *Server) handleUpdateTransaction(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	var req TransactionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	amountCents, feeCents, txType, transactedAt, err := s.validateTransactionInput(r, &req)
	if err != nil {
		var brErr *badRequestError
		if errors.As(err, &brErr) {
			writeJSONError(w, http.StatusBadRequest, brErr.Error())
		} else {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
		}
		return
	}

	res, err := s.db.ExecContext(
		r.Context(),
		`UPDATE transactions
		 SET amount_cents = ?, fee_cents = ?, description = ?, payment_method_id = ?, source_payment_method_id = ?, category_id = ?, tag_id = ?, transacted_at = ?, type = ?
		 WHERE id = ?`,
		amountCents, feeCents, req.Description, req.PaymentMethodID, req.SourcePaymentMethodID, req.CategoryID, req.TagID, transactedAt, txType, id,
	)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to update transaction: "+err.Error())
		return
	}

	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "transaction not found")
		return
	}

	txItem, err := s.getTransactionByID(r, id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, txItem)
}

func (s *Server) handleDeleteTransaction(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	res, err := s.db.ExecContext(r.Context(), "DELETE FROM transactions WHERE id = ?", id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "transaction not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

func (s *Server) handleRefundTransaction(w http.ResponseWriter, r *http.Request) {
	s.setTransactionRefund(w, r, true)
}

func (s *Server) handleCancelRefundTransaction(w http.ResponseWriter, r *http.Request) {
	s.setTransactionRefund(w, r, false)
}

// setTransactionRefund 执行退款 / 撤销退款；两者仅 UPDATE 语句不同，共用守卫与响应。
func (s *Server) setTransactionRefund(w http.ResponseWriter, r *http.Request, refunded bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	existing, err := s.getTransactionByID(r, id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeJSONError(w, http.StatusNotFound, "transaction not found")
			return
		}
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if existing.Type != "expense" && existing.Type != "income" {
		writeJSONError(w, http.StatusBadRequest, "only expense or income transactions can be refunded")
		return
	}

	if refunded {
		// COALESCE 保证幂等：重复退款不刷新首次退款时间
		_, err = s.db.ExecContext(r.Context(), "UPDATE transactions SET refunded_at = COALESCE(refunded_at, ?) WHERE id = ?", time.Now().UTC().Format(time.RFC3339), id)
	} else {
		_, err = s.db.ExecContext(r.Context(), "UPDATE transactions SET refunded_at = NULL WHERE id = ?", id)
	}
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to update refund state: "+err.Error())
		return
	}

	txItem, err := s.getTransactionByID(r, id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, txItem)
}

func (s *Server) validateTransactionInput(r *http.Request, req *TransactionRequest) (int64, int64, string, string, error) {
	txType := strings.ToLower(strings.TrimSpace(req.Type))
	if txType == "" {
		if req.Amount < 0 {
			txType = "expense"
		} else {
			txType = "income"
		}
	}
	if txType != "expense" && txType != "income" && txType != "repayment" && txType != "transfer" {
		return 0, 0, "", "", badRequest("invalid transaction type, must be 'expense', 'income', 'repayment', or 'transfer'")
	}

	var feeCents int64
	if txType == "transfer" {
		if req.Fee < 0 {
			return 0, 0, "", "", badRequest("fee must not be negative")
		}
		feeCents = int64(math.Round(req.Fee * 100))
	} else {
		feeCents = 0
	}

	var amountCents int64
	if txType == "repayment" || txType == "transfer" {
		if req.Amount <= 0 {
			return 0, 0, "", "", badRequest(txType + " amount must be greater than 0")
		}
		amountCents = int64(math.Round(req.Amount * 100))
	} else if txType == "expense" {
		amountCents = -int64(math.Round(math.Abs(req.Amount) * 100))
		if amountCents == 0 {
			return 0, 0, "", "", badRequest("amount must not be 0")
		}
	} else {
		amountCents = int64(math.Round(math.Abs(req.Amount) * 100))
		if amountCents == 0 {
			return 0, 0, "", "", badRequest("amount must not be 0")
		}
	}

	req.Description = strings.TrimSpace(req.Description)
	if req.Description == "" {
		return 0, 0, "", "", badRequest("description cannot be empty")
	}

	// Validate target payment method exists
	var pmType string
	err := s.db.QueryRowContext(r.Context(), "SELECT type FROM payment_methods WHERE id = ?", req.PaymentMethodID).Scan(&pmType)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return 0, 0, "", "", badRequest("payment method does not exist")
		}
		return 0, 0, "", "", fmt.Errorf("failed to query payment method: %w", err)
	}

	if txType == "transfer" {
		if pmType != "asset" {
			return 0, 0, "", "", badRequest("transfer target must be an asset channel")
		}
		if req.SourcePaymentMethodID == nil || *req.SourcePaymentMethodID <= 0 {
			return 0, 0, "", "", badRequest("source payment method is required for transfer")
		}
		if req.PaymentMethodID == *req.SourcePaymentMethodID {
			return 0, 0, "", "", badRequest("source and target payment methods must be different")
		}
		var srcType string
		err := s.db.QueryRowContext(r.Context(), "SELECT type FROM payment_methods WHERE id = ?", *req.SourcePaymentMethodID).Scan(&srcType)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return 0, 0, "", "", badRequest("source payment method does not exist")
			}
			return 0, 0, "", "", fmt.Errorf("failed to query source payment method: %w", err)
		}
		if srcType != "asset" {
			return 0, 0, "", "", badRequest("source payment method must be an asset channel for transfer")
		}

		// Auto-bind system transfer category & tag if not specified
		if req.CategoryID <= 0 || req.TagID <= 0 {
			var sysCatStr, sysTagStr string
			_ = s.db.QueryRowContext(r.Context(), "SELECT value FROM system_meta WHERE key = 'system_category_transfer_id'").Scan(&sysCatStr)
			_ = s.db.QueryRowContext(r.Context(), "SELECT value FROM system_meta WHERE key = 'system_tag_transfer_id'").Scan(&sysTagStr)
			if catID, err := strconv.ParseInt(sysCatStr, 10, 64); err == nil && catID > 0 {
				req.CategoryID = catID
			}
			if tagID, err := strconv.ParseInt(sysTagStr, 10, 64); err == nil && tagID > 0 {
				req.TagID = tagID
			}
		}
	} else if txType == "repayment" {
		if pmType != "liability" {
			return 0, 0, "", "", badRequest("repayment target must be a liability channel")
		}
		if req.SourcePaymentMethodID != nil && *req.SourcePaymentMethodID > 0 {
			var srcType string
			err := s.db.QueryRowContext(r.Context(), "SELECT type FROM payment_methods WHERE id = ?", *req.SourcePaymentMethodID).Scan(&srcType)
			if err != nil {
				if errors.Is(err, sql.ErrNoRows) {
					return 0, 0, "", "", badRequest("source payment method does not exist")
				}
				return 0, 0, "", "", fmt.Errorf("failed to query source payment method: %w", err)
			}
			if srcType != "asset" {
				return 0, 0, "", "", badRequest("source payment method must be an asset channel")
			}
		} else {
			req.SourcePaymentMethodID = nil
		}

		// Auto-bind system repayment category & tag if not specified
		if req.CategoryID <= 0 || req.TagID <= 0 {
			var sysCatStr, sysTagStr string
			_ = s.db.QueryRowContext(r.Context(), "SELECT value FROM system_meta WHERE key = 'system_category_repayment_id'").Scan(&sysCatStr)
			_ = s.db.QueryRowContext(r.Context(), "SELECT value FROM system_meta WHERE key = 'system_tag_repayment_id'").Scan(&sysTagStr)
			if catID, err := strconv.ParseInt(sysCatStr, 10, 64); err == nil && catID > 0 {
				req.CategoryID = catID
			}
			if tagID, err := strconv.ParseInt(sysTagStr, 10, 64); err == nil && tagID > 0 {
				req.TagID = tagID
			}
		}
	} else {
		req.SourcePaymentMethodID = nil
	}

	// Validate category exists
	var catExists int
	err = s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM categories WHERE id = ?", req.CategoryID).Scan(&catExists)
	if err != nil {
		return 0, 0, "", "", fmt.Errorf("failed to query category: %w", err)
	}
	if catExists == 0 {
		return 0, 0, "", "", badRequest("category does not exist")
	}

	// Validate tag exists and belongs to the given category
	var tagBelongs int
	err = s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM tags WHERE id = ? AND category_id = ?", req.TagID, req.CategoryID).Scan(&tagBelongs)
	if err != nil {
		return 0, 0, "", "", fmt.Errorf("failed to query tag: %w", err)
	}
	if tagBelongs == 0 {
		return 0, 0, "", "", badRequest("tag does not belong to specified category")
	}

	// Validate/standardize transacted_at
	transactedAtStr := strings.TrimSpace(req.TransactedAt)
	var finalTransactedAt string
	if transactedAtStr == "" {
		finalTransactedAt = time.Now().UTC().Format(time.RFC3339)
	} else {
		parsedTime, err := parseFlexibleTime(transactedAtStr)
		if err != nil {
			return 0, 0, "", "", badRequest(fmt.Sprintf("invalid transacted_at: %v", err))
		}
		finalTransactedAt = parsedTime.UTC().Format(time.RFC3339)
	}

	return amountCents, feeCents, txType, finalTransactedAt, nil
}

func (s *Server) getTransactionByID(r *http.Request, id int64) (*Transaction, error) {
	var item Transaction
	query := `
		SELECT t.id, t.type, t.amount_cents, t.fee_cents, t.description,
		       t.payment_method_id, COALESCE(pm.name, ''),
		       t.source_payment_method_id, COALESCE(spm.name, ''),
		       t.category_id, COALESCE(c.name, ''),
		       t.tag_id, COALESCE(tg.name, ''),
		       t.transacted_at, t.created_at, t.refunded_at
		FROM transactions t
		LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
		LEFT JOIN payment_methods spm ON t.source_payment_method_id = spm.id
		LEFT JOIN categories c ON t.category_id = c.id
		LEFT JOIN tags tg ON t.tag_id = tg.id
		WHERE t.id = ?
	`
	var srcPMID sql.NullInt64
	var srcPMName sql.NullString
	var refundedAt sql.NullString
	err := s.db.QueryRowContext(r.Context(), query, id).Scan(
		&item.ID, &item.Type, &item.AmountCents, &item.FeeCents, &item.Description,
		&item.PaymentMethodID, &item.PaymentMethodName,
		&srcPMID, &srcPMName,
		&item.CategoryID, &item.CategoryName,
		&item.TagID, &item.TagName,
		&item.TransactedAt, &item.CreatedAt, &refundedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, fmt.Errorf("transaction not found: %w", sql.ErrNoRows)
		}
		return nil, err
	}
	if srcPMID.Valid {
		val := srcPMID.Int64
		item.SourcePaymentMethodID = &val
	}
	if srcPMName.Valid {
		item.SourcePaymentMethodName = srcPMName.String
	}
	if refundedAt.Valid {
		val := refundedAt.String
		item.RefundedAt = &val
	}
	item.Amount = float64(item.AmountCents) / 100.0
	item.Fee = float64(item.FeeCents) / 100.0
	return &item, nil
}

func parseFlexibleTime(str string) (time.Time, error) {
	formats := []string{
		time.RFC3339Nano,
		time.RFC3339,
		"2006-01-02T15:04:05",
		"2006-01-02 15:04:05",
		"2006-01-02",
	}

	for _, format := range formats {
		if t, err := time.Parse(format, str); err == nil {
			return t, nil
		}
	}
	return time.Time{}, errors.New("unsupported time format")
}
