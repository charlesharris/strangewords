package gateway

import (
	"bytes"
	"encoding/base64"
	"fmt"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"strangewords/internal/store"
)

func TestPrivacyPage(t *testing.T) {
	r := newRig(t)

	resp, err := r.cl.Get(r.ts.URL + "/privacy")
	if err != nil {
		t.Fatalf("get /privacy: %v", err)
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}

	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want 200", resp.StatusCode)
	}
	if got := resp.Header.Get("Content-Type"); got != "text/html; charset=utf-8" {
		t.Errorf("Content-Type = %q", got)
	}
	if got := resp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
		t.Errorf("X-Content-Type-Options = %q", got)
	}
	csp := resp.Header.Get("Content-Security-Policy")
	if !strings.HasPrefix(csp, "default-src 'none'") {
		t.Errorf("CSP should start with default-src 'none': %q", csp)
	}
	if !strings.Contains(csp, "frame-ancestors 'none'") {
		t.Errorf("CSP missing frame-ancestors 'none': %q", csp)
	}
	if !bytes.Equal(body, privacyHTML) {
		t.Error("served body is not byte-identical to the embedded privacyHTML")
	}

	lower := strings.ToLower(string(body))
	for _, want := range []string{
		"stranger words privacy policy",
		"privacy@strangewords.app",
		`datetime="2026-10-26"`,
		"october 26, 2026",
	} {
		if !strings.Contains(lower, want) {
			t.Errorf("page missing %q", want)
		}
	}
	if strings.Contains(lower, "<script") {
		t.Error("page must not contain <script")
	}

	// Method pattern rejects non-GET.
	post, err := r.cl.Post(r.ts.URL+"/privacy", "text/plain", strings.NewReader(""))
	if err != nil {
		t.Fatalf("post /privacy: %v", err)
	}
	post.Body.Close()
	if post.StatusCode != http.StatusMethodNotAllowed {
		t.Errorf("POST /privacy status = %d, want 405", post.StatusCode)
	}

	// The request went through the normal metrics middleware chain.
	mresp, err := r.cl.Get(r.ts.URL + "/metrics")
	if err != nil {
		t.Fatalf("get /metrics: %v", err)
	}
	defer mresp.Body.Close()
	mb, _ := io.ReadAll(mresp.Body)
	if !strings.Contains(string(mb), `route="GET /privacy"`) {
		t.Error(`/metrics has no route="GET /privacy" series`)
	}
}

// TestPrivacyPageMatchesCode pins the numbers and claims in privacy.html to
// the live code constants. If one of these fails, the code changed: update
// privacy.html to match (and its effective date), then fix the expectation.
func TestPrivacyPageMatchesCode(t *testing.T) {
	r := newRig(t)
	resp, err := r.cl.Get(r.ts.URL + "/privacy")
	if err != nil {
		t.Fatalf("get /privacy: %v", err)
	}
	defer resp.Body.Close()
	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}
	body := strings.ToLower(string(raw))

	computed := []struct{ name, phrase string }{
		{"store.WaitTTL", fmt.Sprintf("%d minutes", int(store.WaitTTL/time.Minute))},
		{"store.SessionTTL", fmt.Sprintf("%d minutes", int(store.SessionTTL/time.Minute))},
		{"store.IdemTTL", fmt.Sprintf("%d minutes", int(store.IdemTTL/time.Minute))},
		{"limiterMaxIdle", fmt.Sprintf("%d minutes", int(limiterMaxIdle/time.Minute))},
		{"maxReasonLen", fmt.Sprintf("%d characters", maxReasonLen)},
	}
	for _, c := range computed {
		if !strings.Contains(body, c.phrase) {
			t.Errorf("%s changed: privacy.html no longer contains %q; update the page", c.name, c.phrase)
		}
	}

	if store.RevealTTL != 2*time.Minute {
		t.Errorf("store.RevealTTL = %v; update the reveal-window wording in privacy.html", store.RevealTTL)
	}
	if !strings.Contains(body, "two-minute reveal window") {
		t.Error(`privacy.html missing "two-minute reveal window"`)
	}

	tok, err := base64.RawURLEncoding.DecodeString(store.NewToken())
	if err != nil || len(tok) != 32 {
		t.Errorf("store.NewToken decodes to %d bytes (err %v); update \"32-byte\" in privacy.html", len(tok), err)
	}
	if !strings.Contains(body, "random 32-byte token") {
		t.Error(`privacy.html missing "random 32-byte token"`)
	}

	for _, phrase := range []string{
		"no accounts", "ip address", "server logs", "no cookies", "never sent to us",
		"no analytics", "no advertising", "no tracking", "push notifications",
		"robot poet", "outside ai service", "built-in word list", "fly.io", "upstash",
	} {
		if !strings.Contains(body, phrase) {
			t.Errorf("privacy.html missing required phrase %q", phrase)
		}
	}

	for _, banned := range []string{"<script", "<link", "src=", "@import", "url(", " onload=", " onclick="} {
		if strings.Contains(body, banned) {
			t.Errorf("privacy.html must not contain %q", banned)
		}
	}
}
