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
	ID                int64   `json:"id"`
	AmountCents       int64   `json:"amount_cents"`
	Amount            float64 `json:"amount"`
	Description       string  `json:"description"`
	PaymentMethodID   int64   `json:"payment_method_id"`
	PaymentMethodName string  `json:"payment_method_name"`
	CategoryID        int64   `json:"category_id"`
	CategoryName      string  `json:"category_name"`
	TagID             int64   `json:"tag_id"`
	TagName           string  `json:"tag_name"`
	TransactedAt      string  `json:"transacted_at"`
	CreatedAt         string  `json:"created_at"`
}

type TransactionRequest struct {
	Amount          float64 `json:"amount"`
	Description     string  `json:"description"`
	PaymentMethodID int64   `json:"payment_method_id"`
	CategoryID      int64   `json:"category_id"`
	TagID           int64   `json:"tag_id"`
	TransactedAt    string  `json:"transacted_at"`
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

	typeFilter := strings.ToLower(r.URL.Query().Get("type"))
	var query strings.Builder
	query.WriteString(`
		SELECT t.id, t.amount_cents, t.description,
		       t.payment_method_id, COALESCE(pm.name, ''),
		       t.category_id, COALESCE(c.name, ''),
		       t.tag_id, COALESCE(tg.name, ''),
		       t.transacted_at, t.created_at
		FROM transactions t
		LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
		LEFT JOIN categories c ON t.category_id = c.id
		LEFT JOIN tags tg ON t.tag_id = tg.id
	`)

	args := make([]any, 0)
	if typeFilter == "expense" {
		query.WriteString(" WHERE t.amount_cents < 0")
	} else if typeFilter == "income" {
		query.WriteString(" WHERE t.amount_cents > 0")
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
		err := rows.Scan(
			&item.ID, &item.AmountCents, &item.Description,
			&item.PaymentMethodID, &item.PaymentMethodName,
			&item.CategoryID, &item.CategoryName,
			&item.TagID, &item.TagName,
			&item.TransactedAt, &item.CreatedAt,
		)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
			return
		}
		item.Amount = float64(item.AmountCents) / 100.0
		list = append(list, item)
	}

	writeJSON(w, http.StatusOK, list)
}

func (s *Server) handleCreateTransaction(w http.ResponseWriter, r *http.Request) {
	var req TransactionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	amountCents, transactedAt, err := s.validateTransactionInput(r, &req)
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
		`INSERT INTO transactions (amount_cents, description, payment_method_id, category_id, tag_id, transacted_at)
		 VALUES (?, ?, ?, ?, ?, ?)`,
		amountCents, req.Description, req.PaymentMethodID, req.CategoryID, req.TagID, transactedAt,
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

	amountCents, transactedAt, err := s.validateTransactionInput(r, &req)
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
		 SET amount_cents = ?, description = ?, payment_method_id = ?, category_id = ?, tag_id = ?, transacted_at = ?
		 WHERE id = ?`,
		amountCents, req.Description, req.PaymentMethodID, req.CategoryID, req.TagID, transactedAt, id,
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

func (s *Server) validateTransactionInput(r *http.Request, req *TransactionRequest) (int64, string, error) {
	amountCents := int64(math.Round(req.Amount * 100))
	if amountCents == 0 {
		return 0, "", badRequest("amount must not be 0")
	}

	req.Description = strings.TrimSpace(req.Description)
	if req.Description == "" {
		return 0, "", badRequest("description cannot be empty")
	}

	// Validate payment method exists
	var pmExists int
	err := s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM payment_methods WHERE id = ?", req.PaymentMethodID).Scan(&pmExists)
	if err != nil {
		return 0, "", fmt.Errorf("failed to query payment method: %w", err)
	}
	if pmExists == 0 {
		return 0, "", badRequest("payment method does not exist")
	}

	// Validate category exists
	var catExists int
	err = s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM categories WHERE id = ?", req.CategoryID).Scan(&catExists)
	if err != nil {
		return 0, "", fmt.Errorf("failed to query category: %w", err)
	}
	if catExists == 0 {
		return 0, "", badRequest("category does not exist")
	}

	// Validate tag exists and belongs to the given category
	var tagBelongs int
	err = s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM tags WHERE id = ? AND category_id = ?", req.TagID, req.CategoryID).Scan(&tagBelongs)
	if err != nil {
		return 0, "", fmt.Errorf("failed to query tag: %w", err)
	}
	if tagBelongs == 0 {
		return 0, "", badRequest("tag does not belong to specified category")
	}

	// Validate/standardize transacted_at
	transactedAtStr := strings.TrimSpace(req.TransactedAt)
	var finalTransactedAt string
	if transactedAtStr == "" {
		finalTransactedAt = time.Now().UTC().Format(time.RFC3339)
	} else {
		parsedTime, err := parseFlexibleTime(transactedAtStr)
		if err != nil {
			return 0, "", badRequest(fmt.Sprintf("invalid transacted_at: %v", err))
		}
		finalTransactedAt = parsedTime.UTC().Format(time.RFC3339)
	}

	return amountCents, finalTransactedAt, nil
}

func (s *Server) getTransactionByID(r *http.Request, id int64) (*Transaction, error) {
	var item Transaction
	query := `
		SELECT t.id, t.amount_cents, t.description,
		       t.payment_method_id, COALESCE(pm.name, ''),
		       t.category_id, COALESCE(c.name, ''),
		       t.tag_id, COALESCE(tg.name, ''),
		       t.transacted_at, t.created_at
		FROM transactions t
		LEFT JOIN payment_methods pm ON t.payment_method_id = pm.id
		LEFT JOIN categories c ON t.category_id = c.id
		LEFT JOIN tags tg ON t.tag_id = tg.id
		WHERE t.id = ?
	`
	err := s.db.QueryRowContext(r.Context(), query, id).Scan(
		&item.ID, &item.AmountCents, &item.Description,
		&item.PaymentMethodID, &item.PaymentMethodName,
		&item.CategoryID, &item.CategoryName,
		&item.TagID, &item.TagName,
		&item.TransactedAt, &item.CreatedAt,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, errors.New("transaction not found")
		}
		return nil, err
	}
	item.Amount = float64(item.AmountCents) / 100.0
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
