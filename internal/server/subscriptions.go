package server

import (
	"database/sql"
	"encoding/json"
	"math"
	"net/http"
	"strconv"
	"strings"
)

type SubscriptionGroup struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	SortOrder int    `json:"sort_order"`
	CreatedAt string `json:"created_at"`
}

type Subscription struct {
	ID          int64   `json:"id"`
	GroupID     *int64  `json:"group_id"`
	Name        string  `json:"name"`
	AmountCents int64   `json:"amount_cents"`
	Amount      float64 `json:"amount"`
	BillingDay  int     `json:"billing_day"`
	Status      string  `json:"status"`
	CreatedAt   string  `json:"created_at"`
}

const (
	subscriptionGroupColumns = "id, name, sort_order, created_at"
	subscriptionColumns      = "id, group_id, name, amount_cents, billing_day, status, created_at"
)

type rowScanner interface {
	Scan(dest ...any) error
}

func scanSubscriptionGroup(row rowScanner) (SubscriptionGroup, error) {
	var group SubscriptionGroup
	err := row.Scan(&group.ID, &group.Name, &group.SortOrder, &group.CreatedAt)
	return group, err
}

func scanSubscription(row rowScanner) (Subscription, error) {
	var sub Subscription
	var groupID sql.NullInt64
	err := row.Scan(&sub.ID, &groupID, &sub.Name, &sub.AmountCents, &sub.BillingDay, &sub.Status, &sub.CreatedAt)
	if groupID.Valid {
		sub.GroupID = &groupID.Int64
	}
	sub.Amount = float64(sub.AmountCents) / 100
	return sub, err
}

// Subscription Groups Handlers

func (s *Server) handleListSubscriptionGroups(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.QueryContext(r.Context(), "SELECT "+subscriptionGroupColumns+" FROM subscription_groups ORDER BY sort_order ASC, id ASC")
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	groups := make([]SubscriptionGroup, 0)
	for rows.Next() {
		group, err := scanSubscriptionGroup(rows)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
			return
		}
		groups = append(groups, group)
	}

	writeJSON(w, http.StatusOK, groups)
}

func (s *Server) handleCreateSubscriptionGroup(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name      string `json:"name"`
		SortOrder int    `json:"sort_order"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeJSONError(w, http.StatusBadRequest, "name cannot be empty")
		return
	}

	res, err := s.db.ExecContext(r.Context(), "INSERT INTO subscription_groups (name, sort_order) VALUES (?, ?)", req.Name, req.SortOrder)
	if err != nil {
		if isUniqueConstraintError(err) {
			writeJSONError(w, http.StatusBadRequest, "subscription group already exists")
			return
		}
		writeJSONError(w, http.StatusInternalServerError, "failed to create subscription group: "+err.Error())
		return
	}
	id, err := res.LastInsertId()
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to retrieve id: "+err.Error())
		return
	}

	group, err := scanSubscriptionGroup(s.db.QueryRowContext(r.Context(), "SELECT "+subscriptionGroupColumns+" FROM subscription_groups WHERE id = ?", id))
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to read subscription group: "+err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, group)
}

func (s *Server) handleUpdateSubscriptionGroup(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	var req struct {
		Name      string `json:"name"`
		SortOrder int    `json:"sort_order"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		writeJSONError(w, http.StatusBadRequest, "name cannot be empty")
		return
	}

	res, err := s.db.ExecContext(r.Context(), "UPDATE subscription_groups SET name = ?, sort_order = ? WHERE id = ?", req.Name, req.SortOrder, id)
	if err != nil {
		if isUniqueConstraintError(err) {
			writeJSONError(w, http.StatusBadRequest, "subscription group already exists")
			return
		}
		writeJSONError(w, http.StatusInternalServerError, "failed to update subscription group: "+err.Error())
		return
	}
	if rowsAffected, _ := res.RowsAffected(); rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "subscription group not found")
		return
	}

	group, err := scanSubscriptionGroup(s.db.QueryRowContext(r.Context(), "SELECT "+subscriptionGroupColumns+" FROM subscription_groups WHERE id = ?", id))
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to read subscription group: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, group)
}

func (s *Server) handleDeleteSubscriptionGroup(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	res, err := s.db.ExecContext(r.Context(), "DELETE FROM subscription_groups WHERE id = ?", id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if rowsAffected, _ := res.RowsAffected(); rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "subscription group not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// Subscriptions Handlers

func (s *Server) handleListSubscriptions(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.QueryContext(r.Context(), "SELECT "+subscriptionColumns+" FROM subscriptions ORDER BY group_id IS NULL, group_id ASC, billing_day ASC, id ASC")
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	subs := make([]Subscription, 0)
	for rows.Next() {
		sub, err := scanSubscription(rows)
		if err != nil {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
			return
		}
		subs = append(subs, sub)
	}

	writeJSON(w, http.StatusOK, subs)
}

type subscriptionRequest struct {
	Name       string  `json:"name"`
	GroupID    *int64  `json:"group_id"`
	Amount     float64 `json:"amount"`
	BillingDay int     `json:"billing_day"`
	Status     string  `json:"status"`
}

// normalizeSubscriptionInput validates a create/update payload and resolves optional fields.
func normalizeSubscriptionInput(req subscriptionRequest) (string, *int64, int64, string, error) {
	name := strings.TrimSpace(req.Name)
	if name == "" {
		return "", nil, 0, "", badRequest("name cannot be empty")
	}
	if req.Amount < 0.01 || req.Amount > 1000000 {
		return "", nil, 0, "", badRequest("amount must be between 0.01 and 1000000")
	}
	cents := int64(math.Round(req.Amount * 100))
	if cents <= 0 {
		return "", nil, 0, "", badRequest("amount must be at least 0.01")
	}
	if req.BillingDay < 1 || req.BillingDay > 31 {
		return "", nil, 0, "", badRequest("billing_day must be between 1 and 31")
	}
	status := strings.TrimSpace(req.Status)
	if status == "" {
		status = "active"
	}
	if status != "active" && status != "paused" {
		return "", nil, 0, "", badRequest("status must be 'active' or 'paused'")
	}
	var groupID *int64
	if req.GroupID != nil {
		if *req.GroupID < 0 {
			return "", nil, 0, "", badRequest("group_id cannot be negative")
		}
		if *req.GroupID > 0 {
			groupID = req.GroupID
		}
	}
	return name, groupID, cents, status, nil
}

func (s *Server) subscriptionGroupExists(r *http.Request, groupID *int64) (bool, error) {
	if groupID == nil {
		return true, nil
	}
	var count int
	if err := s.db.QueryRowContext(r.Context(), "SELECT COUNT(*) FROM subscription_groups WHERE id = ?", *groupID).Scan(&count); err != nil {
		return false, err
	}
	return count > 0, nil
}

func (s *Server) handleCreateSubscription(w http.ResponseWriter, r *http.Request) {
	var req subscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	name, groupID, cents, status, err := normalizeSubscriptionInput(req)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, err.Error())
		return
	}
	exists, err := s.subscriptionGroupExists(r, groupID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if !exists {
		writeJSONError(w, http.StatusBadRequest, "subscription group not found")
		return
	}

	res, err := s.db.ExecContext(r.Context(),
		"INSERT INTO subscriptions (group_id, name, amount_cents, billing_day, status) VALUES (?, ?, ?, ?, ?)",
		groupID, name, cents, req.BillingDay, status)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to create subscription: "+err.Error())
		return
	}
	id, err := res.LastInsertId()
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to retrieve id: "+err.Error())
		return
	}

	sub, err := scanSubscription(s.db.QueryRowContext(r.Context(), "SELECT "+subscriptionColumns+" FROM subscriptions WHERE id = ?", id))
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to read subscription: "+err.Error())
		return
	}

	writeJSON(w, http.StatusCreated, sub)
}

func (s *Server) handleUpdateSubscription(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	var req subscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	name, groupID, cents, status, err := normalizeSubscriptionInput(req)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, err.Error())
		return
	}
	exists, err := s.subscriptionGroupExists(r, groupID)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if !exists {
		writeJSONError(w, http.StatusBadRequest, "subscription group not found")
		return
	}

	res, err := s.db.ExecContext(r.Context(),
		"UPDATE subscriptions SET group_id = ?, name = ?, amount_cents = ?, billing_day = ?, status = ? WHERE id = ?",
		groupID, name, cents, req.BillingDay, status, id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to update subscription: "+err.Error())
		return
	}
	if rowsAffected, _ := res.RowsAffected(); rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "subscription not found")
		return
	}

	sub, err := scanSubscription(s.db.QueryRowContext(r.Context(), "SELECT "+subscriptionColumns+" FROM subscriptions WHERE id = ?", id))
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "failed to read subscription: "+err.Error())
		return
	}

	writeJSON(w, http.StatusOK, sub)
}

func (s *Server) handleDeleteSubscription(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	res, err := s.db.ExecContext(r.Context(), "DELETE FROM subscriptions WHERE id = ?", id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if rowsAffected, _ := res.RowsAffected(); rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "subscription not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}
