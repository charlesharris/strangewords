package gateway

import (
	"bytes"
	"io"
	"net/http"
	"strings"
	"testing"
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
