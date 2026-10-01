package server

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"strconv"
	"strings"
)

type PaymentMethod struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	SortOrder int    `json:"sort_order"`
	CreatedAt string `json:"created_at"`
}

type Tag struct {
	ID         int64  `json:"id"`
	CategoryID int64  `json:"category_id"`
	Name       string `json:"name"`
	SortOrder  int    `json:"sort_order"`
	CreatedAt  string `json:"created_at"`
}

type Category struct {
	ID        int64  `json:"id"`
	Name      string `json:"name"`
	SortOrder int    `json:"sort_order"`
	CreatedAt string `json:"created_at"`
	Tags      []Tag  `json:"tags"`
}

// Payment Methods Handlers

func (s *Server) handleListPaymentMethods(w http.ResponseWriter, r *http.Request) {
	rows, err := s.db.QueryContext(r.Context(), "SELECT id, name, sort_order, created_at FROM payment_methods ORDER BY sort_order ASC, id ASC")
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	list := make([]PaymentMethod, 0)
	for rows.Next() {
		var pm PaymentMethod
		if err := rows.Scan(&pm.ID, &pm.Name, &pm.SortOrder, &pm.CreatedAt); err != nil {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
			return
		}
		list = append(list, pm)
	}

	writeJSON(w, http.StatusOK, list)
}

func (s *Server) handleCreatePaymentMethod(w http.ResponseWriter, r *http.Request) {
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

	res, err := s.db.ExecContext(r.Context(), "INSERT INTO payment_methods (name, sort_order) VALUES (?, ?)", req.Name, req.SortOrder)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "payment method already exists or invalid data")
		return
	}

	id, _ := res.LastInsertId()
	var pm PaymentMethod
	_ = s.db.QueryRowContext(r.Context(), "SELECT id, name, sort_order, created_at FROM payment_methods WHERE id = ?", id).
		Scan(&pm.ID, &pm.Name, &pm.SortOrder, &pm.CreatedAt)

	writeJSON(w, http.StatusCreated, pm)
}

func (s *Server) handleUpdatePaymentMethod(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
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

	res, err := s.db.ExecContext(r.Context(), "UPDATE payment_methods SET name = ?, sort_order = ? WHERE id = ?", req.Name, req.SortOrder, id)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "duplicate name or invalid update")
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "payment method not found")
		return
	}

	var pm PaymentMethod
	_ = s.db.QueryRowContext(r.Context(), "SELECT id, name, sort_order, created_at FROM payment_methods WHERE id = ?", id).
		Scan(&pm.ID, &pm.Name, &pm.SortOrder, &pm.CreatedAt)

	writeJSON(w, http.StatusOK, pm)
}

func (s *Server) handleDeletePaymentMethod(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	var count int
	err = s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM transactions WHERE payment_method_id = ?", id).Scan(&count)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if count > 0 {
		writeJSONError(w, http.StatusConflict, "该支付途径已有关联账单，禁止删除")
		return
	}

	res, err := s.db.ExecContext(r.Context(), "DELETE FROM payment_methods WHERE id = ?", id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "payment method not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// Categories Handlers

func (s *Server) handleListCategories(w http.ResponseWriter, r *http.Request) {
	catRows, err := s.db.QueryContext(r.Context(), "SELECT id, name, sort_order, created_at FROM categories ORDER BY sort_order ASC, id ASC")
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer catRows.Close()

	categories := make([]Category, 0)
	catIndex := make(map[int64]int)

	for catRows.Next() {
		var cat Category
		cat.Tags = make([]Tag, 0)
		if err := catRows.Scan(&cat.ID, &cat.Name, &cat.SortOrder, &cat.CreatedAt); err != nil {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
			return
		}
		catIndex[cat.ID] = len(categories)
		categories = append(categories, cat)
	}

	tagRows, err := s.db.QueryContext(r.Context(), "SELECT id, category_id, name, sort_order, created_at FROM tags ORDER BY sort_order ASC, id ASC")
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer tagRows.Close()

	for tagRows.Next() {
		var tag Tag
		if err := tagRows.Scan(&tag.ID, &tag.CategoryID, &tag.Name, &tag.SortOrder, &tag.CreatedAt); err != nil {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
			return
		}
		if idx, ok := catIndex[tag.CategoryID]; ok {
			categories[idx].Tags = append(categories[idx].Tags, tag)
		}
	}

	writeJSON(w, http.StatusOK, categories)
}

func (s *Server) handleCreateCategory(w http.ResponseWriter, r *http.Request) {
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

	res, err := s.db.ExecContext(r.Context(), "INSERT INTO categories (name, sort_order) VALUES (?, ?)", req.Name, req.SortOrder)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "category already exists or invalid data")
		return
	}

	id, _ := res.LastInsertId()
	var cat Category
	cat.Tags = make([]Tag, 0)
	_ = s.db.QueryRowContext(r.Context(), "SELECT id, name, sort_order, created_at FROM categories WHERE id = ?", id).
		Scan(&cat.ID, &cat.Name, &cat.SortOrder, &cat.CreatedAt)

	writeJSON(w, http.StatusCreated, cat)
}

func (s *Server) handleUpdateCategory(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
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

	res, err := s.db.ExecContext(r.Context(), "UPDATE categories SET name = ?, sort_order = ? WHERE id = ?", req.Name, req.SortOrder, id)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "duplicate name or invalid update")
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "category not found")
		return
	}

	var cat Category
	cat.Tags = make([]Tag, 0)
	_ = s.db.QueryRowContext(r.Context(), "SELECT id, name, sort_order, created_at FROM categories WHERE id = ?", id).
		Scan(&cat.ID, &cat.Name, &cat.SortOrder, &cat.CreatedAt)

	writeJSON(w, http.StatusOK, cat)
}

func (s *Server) handleDeleteCategory(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	// Guard 1: Direct transaction reference
	var catTransCount int
	err = s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM transactions WHERE category_id = ?", id).Scan(&catTransCount)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if catTransCount > 0 {
		writeJSONError(w, http.StatusConflict, "该消费类型已有关联账单，禁止删除")
		return
	}

	// Guard 2: Tag transaction reference
	var tagTransCount int
	err = s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM transactions WHERE tag_id IN (SELECT id FROM tags WHERE category_id = ?)", id).Scan(&tagTransCount)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if tagTransCount > 0 {
		writeJSONError(w, http.StatusConflict, "该消费类型已有关联账单，禁止删除")
		return
	}

	// In single transaction, delete tags and category
	tx, err := s.db.BeginTx(r.Context(), nil)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer tx.Rollback()

	if _, err := tx.ExecContext(r.Context(), "DELETE FROM tags WHERE category_id = ?", id); err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}

	res, err := tx.ExecContext(r.Context(), "DELETE FROM categories WHERE id = ?", id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "category not found")
		return
	}

	if err := tx.Commit(); err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// Tags Handlers

func (s *Server) handleListTags(w http.ResponseWriter, r *http.Request) {
	catIDStr := r.URL.Query().Get("category_id")

	var rows *sql.Rows
	var err error
	if catIDStr != "" {
		catID, parseErr := strconv.ParseInt(catIDStr, 10, 64)
		if parseErr != nil {
			writeJSONError(w, http.StatusBadRequest, "invalid category_id")
			return
		}
		rows, err = s.db.QueryContext(r.Context(), "SELECT id, category_id, name, sort_order, created_at FROM tags WHERE category_id = ? ORDER BY sort_order ASC, id ASC", catID)
	} else {
		rows, err = s.db.QueryContext(r.Context(), "SELECT id, category_id, name, sort_order, created_at FROM tags ORDER BY sort_order ASC, id ASC")
	}

	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	tags := make([]Tag, 0)
	for rows.Next() {
		var tag Tag
		if err := rows.Scan(&tag.ID, &tag.CategoryID, &tag.Name, &tag.SortOrder, &tag.CreatedAt); err != nil {
			writeJSONError(w, http.StatusInternalServerError, err.Error())
			return
		}
		tags = append(tags, tag)
	}

	writeJSON(w, http.StatusOK, tags)
}

func (s *Server) handleCreateTag(w http.ResponseWriter, r *http.Request) {
	var req struct {
		CategoryID int64  `json:"category_id"`
		Name       string `json:"name"`
		SortOrder  int    `json:"sort_order"`
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
	if req.CategoryID <= 0 {
		writeJSONError(w, http.StatusBadRequest, "valid category_id is required")
		return
	}

	res, err := s.db.ExecContext(r.Context(), "INSERT INTO tags (category_id, name, sort_order) VALUES (?, ?, ?)", req.CategoryID, req.Name, req.SortOrder)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "tag already exists in this category or invalid category")
		return
	}

	id, _ := res.LastInsertId()
	var tag Tag
	_ = s.db.QueryRowContext(r.Context(), "SELECT id, category_id, name, sort_order, created_at FROM tags WHERE id = ?", id).
		Scan(&tag.ID, &tag.CategoryID, &tag.Name, &tag.SortOrder, &tag.CreatedAt)

	writeJSON(w, http.StatusCreated, tag)
}

func (s *Server) handleUpdateTag(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
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

	res, err := s.db.ExecContext(r.Context(), "UPDATE tags SET name = ?, sort_order = ? WHERE id = ?", req.Name, req.SortOrder, id)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "duplicate tag name or invalid update")
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "tag not found")
		return
	}

	var tag Tag
	_ = s.db.QueryRowContext(r.Context(), "SELECT id, category_id, name, sort_order, created_at FROM tags WHERE id = ?", id).
		Scan(&tag.ID, &tag.CategoryID, &tag.Name, &tag.SortOrder, &tag.CreatedAt)

	writeJSON(w, http.StatusOK, tag)
}

func (s *Server) handleDeleteTag(w http.ResponseWriter, r *http.Request) {
	idStr := r.PathValue("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid id")
		return
	}

	var count int
	err = s.db.QueryRowContext(r.Context(), "SELECT COUNT(1) FROM transactions WHERE tag_id = ?", id).Scan(&count)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if count > 0 {
		writeJSONError(w, http.StatusConflict, "该细分标签已有关联账单，禁止删除")
		return
	}

	res, err := s.db.ExecContext(r.Context(), "DELETE FROM tags WHERE id = ?", id)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, err.Error())
		return
	}
	rowsAffected, _ := res.RowsAffected()
	if rowsAffected == 0 {
		writeJSONError(w, http.StatusNotFound, "tag not found")
		return
	}

	writeJSON(w, http.StatusOK, map[string]bool{"success": true})
}

// Helpers
func writeJSON(w http.ResponseWriter, statusCode int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(data)
}

func writeJSONError(w http.ResponseWriter, statusCode int, message string) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(statusCode)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": message})
}
