package server

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"testing"
)

func doSubRequest(t *testing.T, s *Server, method, path, token string, body any) *httptest.ResponseRecorder {
	t.Helper()
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal body: %v", err)
		}
		reader = bytes.NewReader(data)
	}
	req := httptest.NewRequest(method, path, reader)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	s.ServeHTTP(rec, req)
	return rec
}

func TestSubscriptionGroupCRUD(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	rec := doSubRequest(t, s, "POST", "/api/subscription-groups", token, map[string]any{"name": "影音娱乐", "sort_order": 2})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create group status = %d: %s", rec.Code, rec.Body.String())
	}
	var groupA SubscriptionGroup
	if err := json.NewDecoder(rec.Body).Decode(&groupA); err != nil {
		t.Fatalf("decode group: %v", err)
	}
	if groupA.Name != "影音娱乐" || groupA.SortOrder != 2 {
		t.Errorf("unexpected group: %+v", groupA)
	}

	rec = doSubRequest(t, s, "POST", "/api/subscription-groups", token, map[string]any{"name": "软件工具", "sort_order": 1})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create second group status = %d: %s", rec.Code, rec.Body.String())
	}
	var groupB SubscriptionGroup
	if err := json.NewDecoder(rec.Body).Decode(&groupB); err != nil {
		t.Fatalf("decode group: %v", err)
	}

	rec = doSubRequest(t, s, "GET", "/api/subscription-groups", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("list groups status = %d: %s", rec.Code, rec.Body.String())
	}
	var groups []SubscriptionGroup
	if err := json.NewDecoder(rec.Body).Decode(&groups); err != nil {
		t.Fatalf("decode groups: %v", err)
	}
	if len(groups) != 2 || groups[0].ID != groupB.ID || groups[1].ID != groupA.ID {
		t.Errorf("groups not ordered by sort_order: %+v", groups)
	}

	rec = doSubRequest(t, s, "PUT", "/api/subscription-groups/"+strconv.FormatInt(groupA.ID, 10), token, map[string]any{"name": "影音", "sort_order": 2})
	if rec.Code != http.StatusOK {
		t.Fatalf("rename group status = %d: %s", rec.Code, rec.Body.String())
	}
	var renamed SubscriptionGroup
	if err := json.NewDecoder(rec.Body).Decode(&renamed); err != nil {
		t.Fatalf("decode renamed group: %v", err)
	}
	if renamed.Name != "影音" || renamed.SortOrder != 2 {
		t.Errorf("unexpected renamed group: %+v", renamed)
	}

	// Duplicate names are rejected case-insensitively.
	rec = doSubRequest(t, s, "POST", "/api/subscription-groups", token, map[string]any{"name": "Apple"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create Apple group status = %d: %s", rec.Code, rec.Body.String())
	}
	for _, body := range []map[string]any{
		{"name": "Apple"},
		{"name": "apple"},
		{"name": "  "},
	} {
		rec = doSubRequest(t, s, "POST", "/api/subscription-groups", token, body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("create %v status = %d, want 400", body, rec.Code)
		}
	}

	rec = doSubRequest(t, s, "PUT", "/api/subscription-groups/9999", token, map[string]any{"name": "不存在", "sort_order": 0})
	if rec.Code != http.StatusNotFound {
		t.Errorf("update missing group status = %d, want 404", rec.Code)
	}
	rec = doSubRequest(t, s, "DELETE", "/api/subscription-groups/9999", token, nil)
	if rec.Code != http.StatusNotFound {
		t.Errorf("delete missing group status = %d, want 404", rec.Code)
	}
	rec = doSubRequest(t, s, "PUT", "/api/subscription-groups/abc", token, map[string]any{"name": "x", "sort_order": 0})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("update invalid id status = %d, want 400", rec.Code)
	}

	// Deleting a group detaches its subscriptions instead of deleting them.
	rec = doSubRequest(t, s, "POST", "/api/subscriptions", token, map[string]any{
		"name": "Netflix", "group_id": groupA.ID, "amount": 68, "billing_day": 15,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create subscription status = %d: %s", rec.Code, rec.Body.String())
	}
	var sub Subscription
	if err := json.NewDecoder(rec.Body).Decode(&sub); err != nil {
		t.Fatalf("decode subscription: %v", err)
	}

	rec = doSubRequest(t, s, "DELETE", "/api/subscription-groups/"+strconv.FormatInt(groupA.ID, 10), token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("delete group status = %d: %s", rec.Code, rec.Body.String())
	}

	rec = doSubRequest(t, s, "GET", "/api/subscriptions", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("list subscriptions status = %d: %s", rec.Code, rec.Body.String())
	}
	var subs []Subscription
	if err := json.NewDecoder(rec.Body).Decode(&subs); err != nil {
		t.Fatalf("decode subscriptions: %v", err)
	}
	if len(subs) != 1 || subs[0].ID != sub.ID || subs[0].GroupID != nil {
		t.Errorf("expected detached subscription to remain, got %+v", subs)
	}

	// Every subscription endpoint requires authentication.
	for _, tc := range []struct{ method, path string }{
		{"GET", "/api/subscription-groups"},
		{"POST", "/api/subscription-groups"},
		{"PUT", "/api/subscription-groups/1"},
		{"DELETE", "/api/subscription-groups/1"},
		{"GET", "/api/subscriptions"},
		{"POST", "/api/subscriptions"},
		{"PUT", "/api/subscriptions/1"},
		{"DELETE", "/api/subscriptions/1"},
	} {
		rec = doSubRequest(t, s, tc.method, tc.path, "", nil)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s without auth status = %d, want 401", tc.method, tc.path, rec.Code)
		}
	}
}

func TestSubscriptionCRUDAndValidation(t *testing.T) {
	s, token, cleanup := setupTestServer(t)
	defer cleanup()

	rec := doSubRequest(t, s, "POST", "/api/subscription-groups", token, map[string]any{"name": "软件工具", "sort_order": 1})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create group status = %d: %s", rec.Code, rec.Body.String())
	}
	var group SubscriptionGroup
	if err := json.NewDecoder(rec.Body).Decode(&group); err != nil {
		t.Fatalf("decode group: %v", err)
	}

	rec = doSubRequest(t, s, "POST", "/api/subscriptions", token, map[string]any{
		"name": "Notion", "group_id": group.ID, "amount": 72, "billing_day": 1,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create grouped subscription status = %d: %s", rec.Code, rec.Body.String())
	}
	var grouped Subscription
	if err := json.NewDecoder(rec.Body).Decode(&grouped); err != nil {
		t.Fatalf("decode grouped subscription: %v", err)
	}
	if grouped.AmountCents != 7200 || grouped.Amount != 72 || grouped.Status != "active" || grouped.GroupID == nil || *grouped.GroupID != group.ID {
		t.Errorf("unexpected grouped subscription: %+v", grouped)
	}

	rec = doSubRequest(t, s, "POST", "/api/subscriptions", token, map[string]any{
		"name": "临时订阅", "amount": 12.345, "billing_day": 28,
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create ungrouped subscription status = %d: %s", rec.Code, rec.Body.String())
	}
	var ungrouped Subscription
	if err := json.NewDecoder(rec.Body).Decode(&ungrouped); err != nil {
		t.Fatalf("decode ungrouped subscription: %v", err)
	}
	if ungrouped.GroupID != nil {
		t.Errorf("expected null group_id for ungrouped subscription, got %v", *ungrouped.GroupID)
	}
	if ungrouped.AmountCents != 1235 || ungrouped.Amount != 12.35 {
		t.Errorf("amount rounding = %d / %v, want 1235 / 12.35", ungrouped.AmountCents, ungrouped.Amount)
	}

	rec = doSubRequest(t, s, "POST", "/api/subscriptions", token, map[string]any{
		"name": "暂停项", "amount": 35, "billing_day": 28, "status": "paused",
	})
	if rec.Code != http.StatusCreated {
		t.Fatalf("create paused subscription status = %d: %s", rec.Code, rec.Body.String())
	}

	rec = doSubRequest(t, s, "GET", "/api/subscriptions", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("list subscriptions status = %d: %s", rec.Code, rec.Body.String())
	}
	var subs []Subscription
	if err := json.NewDecoder(rec.Body).Decode(&subs); err != nil {
		t.Fatalf("decode subscriptions: %v", err)
	}
	if len(subs) != 3 {
		t.Fatalf("expected 3 subscriptions, got %+v", subs)
	}
	if subs[0].ID != grouped.ID || subs[len(subs)-1].GroupID != nil {
		t.Errorf("unexpected subscription order: %+v", subs)
	}

	// Invalid payloads are rejected before touching the database.
	invalid := []map[string]any{
		{"name": "零金额", "amount": 0, "billing_day": 1},
		{"name": "负金额", "amount": -1, "billing_day": 1},
		{"name": "不足一分", "amount": 0.001, "billing_day": 1},
		{"name": "超过上限", "amount": 1000000.01, "billing_day": 1},
		{"name": "非法日 0", "amount": 10, "billing_day": 0},
		{"name": "非法日 32", "amount": 10, "billing_day": 32},
		{"name": "非法状态", "amount": 10, "billing_day": 1, "status": "archived"},
		{"name": "不存在的分组", "amount": 10, "billing_day": 1, "group_id": 9999},
		{"name": "负分组", "amount": 10, "billing_day": 1, "group_id": -1},
		{"name": " ", "amount": 10, "billing_day": 1},
	}
	for _, body := range invalid {
		rec = doSubRequest(t, s, "POST", "/api/subscriptions", token, body)
		if rec.Code != http.StatusBadRequest {
			t.Errorf("create %v status = %d, want 400 (%s)", body, rec.Code, rec.Body.String())
		}
	}

	// Full update moves the subscription into the group and pauses it.
	rec = doSubRequest(t, s, "PUT", "/api/subscriptions/"+strconv.FormatInt(ungrouped.ID, 10), token, map[string]any{
		"name": "临时订阅", "group_id": group.ID, "amount": 13, "billing_day": 5, "status": "paused",
	})
	if rec.Code != http.StatusOK {
		t.Fatalf("update subscription status = %d: %s", rec.Code, rec.Body.String())
	}
	var updated Subscription
	if err := json.NewDecoder(rec.Body).Decode(&updated); err != nil {
		t.Fatalf("decode updated subscription: %v", err)
	}
	if updated.Status != "paused" || updated.GroupID == nil || *updated.GroupID != group.ID || updated.BillingDay != 5 || updated.AmountCents != 1300 {
		t.Errorf("unexpected updated subscription: %+v", updated)
	}

	rec = doSubRequest(t, s, "PUT", "/api/subscriptions/9999", token, map[string]any{
		"name": "不存在", "amount": 10, "billing_day": 1,
	})
	if rec.Code != http.StatusNotFound {
		t.Errorf("update missing subscription status = %d, want 404", rec.Code)
	}
	rec = doSubRequest(t, s, "PUT", "/api/subscriptions/abc", token, map[string]any{
		"name": "非法 id", "amount": 10, "billing_day": 1,
	})
	if rec.Code != http.StatusBadRequest {
		t.Errorf("update invalid id status = %d, want 400", rec.Code)
	}

	rec = doSubRequest(t, s, "DELETE", "/api/subscriptions/"+strconv.FormatInt(grouped.ID, 10), token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("delete subscription status = %d: %s", rec.Code, rec.Body.String())
	}
	rec = doSubRequest(t, s, "DELETE", "/api/subscriptions/"+strconv.FormatInt(grouped.ID, 10), token, nil)
	if rec.Code != http.StatusNotFound {
		t.Errorf("second delete status = %d, want 404", rec.Code)
	}

	rec = doSubRequest(t, s, "GET", "/api/subscriptions", token, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("list subscriptions status = %d: %s", rec.Code, rec.Body.String())
	}
	if err := json.NewDecoder(rec.Body).Decode(&subs); err != nil {
		t.Fatalf("decode subscriptions: %v", err)
	}
	for _, sub := range subs {
		if sub.ID == grouped.ID {
			t.Errorf("deleted subscription still listed: %+v", sub)
		}
	}
}
