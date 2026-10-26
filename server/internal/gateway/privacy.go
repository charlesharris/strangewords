package gateway

import (
	_ "embed"
	"net/http"
)

// privacyHTML is the public privacy policy page, embedded at build time so the
// binary is self-contained.
//
//go:embed privacy.html
var privacyHTML []byte

// handlePrivacy serves the static privacy policy. This is the privacy policy
// URL for App Store Connect / TestFlight (https://api.strangewords.app/privacy).
//
// The page content must track the code: every claim on it was verified against
// the implementation, and privacy_test.go pins the numbers (TTLs, token size,
// report reason cap, limiter idle) to the live constants so a tune fails the
// build until privacy.html is updated.
//
// The handler reads nothing from the request and does no I/O.
func (s *Server) handlePrivacy(w http.ResponseWriter, r *http.Request) {
	h := w.Header()
	h.Set("Content-Type", "text/html; charset=utf-8")
	h.Set("X-Content-Type-Options", "nosniff")
	h.Set("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'")
	h.Set("Referrer-Policy", "no-referrer")
	h.Set("Cache-Control", "public, max-age=3600")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(privacyHTML)
}
