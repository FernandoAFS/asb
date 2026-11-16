package main

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// testHandler builds a proxy handler from a routes JSON array.
func testHandler(t *testing.T, routesJSON string) http.Handler {
	t.Helper()
	cfg, err := LoadConfig(writeConfig(t, `{"routes":`+routesJSON+`}`))
	if err != nil {
		t.Fatalf("load config: %v", err)
	}
	h, err := newProxyHandler(cfg, nil)
	if err != nil {
		t.Fatalf("new handler: %v", err)
	}
	return h
}

func TestInjectsHeaderAndStripsPrefix(t *testing.T) {
	t.Setenv("TOKEN", "secret")
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "%s|%s|%s", r.Header.Get("Authorization"), r.URL.Path, r.URL.RawQuery)
	}))
	defer upstream.Close()

	front := httptest.NewServer(testHandler(t, fmt.Sprintf(
		`[{"name":"o","prefix":"/openai","upstream":%q,"strip_prefix":true,"inject":[{"in":"header","name":"Authorization","value":"Bearer ${TOKEN}"}]}]`,
		upstream.URL)))
	defer front.Close()

	req, _ := http.NewRequest(http.MethodGet, front.URL+"/openai/v1/models?foo=bar", nil)
	// An inbound credential must not shadow the injected one.
	req.Header.Set("Authorization", "Bearer evil")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)

	if got, want := string(body), "Bearer secret|/v1/models|foo=bar"; got != want {
		t.Fatalf("upstream saw %q, want %q", got, want)
	}
}

func TestKeepsPrefixWhenNotStripped(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, r.URL.Path)
	}))
	defer upstream.Close()

	front := httptest.NewServer(testHandler(t, fmt.Sprintf(
		`[{"name":"g","prefix":"/github","upstream":%q}]`, upstream.URL)))
	defer front.Close()

	resp, err := http.Get(front.URL + "/github/user")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if got, want := string(body), "/github/user"; got != want {
		t.Fatalf("upstream path = %q, want %q", got, want)
	}
}

func TestInjectsQueryParameter(t *testing.T) {
	t.Setenv("TOKEN", "secret")
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, r.URL.Query().Get("api_key"))
	}))
	defer upstream.Close()

	front := httptest.NewServer(testHandler(t, fmt.Sprintf(
		`[{"name":"s","prefix":"/s","upstream":%q,"inject":[{"in":"query","name":"api_key","value":"${TOKEN}"}]}]`,
		upstream.URL)))
	defer front.Close()

	resp, err := http.Get(front.URL + "/s?api_key=evil")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if got, want := string(body), "secret"; got != want {
		t.Fatalf("query parameter = %q, want %q", got, want)
	}
}

func TestLongestPrefixWins(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "upstream")
	}))
	defer upstream.Close()

	front := httptest.NewServer(testHandler(t, fmt.Sprintf(
		`[{"name":"broad","prefix":"/a","upstream":%q},{"name":"narrow","prefix":"/a/b","upstream":%q,"strip_prefix":true}]`,
		upstream.URL, upstream.URL)))
	defer front.Close()

	resp, err := http.Get(front.URL + "/a/b/x")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	// The narrow route strips /a/b, so the upstream sees /x, not /a/b/x.
	if got, want := string(body), "upstream"; got != want {
		t.Fatalf("body = %q, want %q", got, want)
	}
}

func TestUnmatchedPathIsNotFound(t *testing.T) {
	front := httptest.NewServer(testHandler(t, `[{"name":"a","prefix":"/a","upstream":"https://x.example.com"}]`))
	defer front.Close()

	resp, err := http.Get(front.URL + "/nope")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("status = %d, want 404", resp.StatusCode)
	}
}

func TestUpstreamFailureIsBadGateway(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {}))
	upstream.Close()

	front := httptest.NewServer(testHandler(t, fmt.Sprintf(
		`[{"name":"a","prefix":"/a","upstream":%q}]`, upstream.URL)))
	defer front.Close()

	resp, err := http.Get(front.URL + "/a")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusBadGateway {
		t.Fatalf("status = %d, want 502", resp.StatusCode)
	}
}

func TestResponseStreams(t *testing.T) {
	release := make(chan struct{})
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		f := w.(http.Flusher)
		_, _ = io.WriteString(w, "data: one\n\n")
		f.Flush()
		<-release
		_, _ = io.WriteString(w, "data: two\n\n")
		f.Flush()
	}))
	defer upstream.Close()

	front := httptest.NewServer(testHandler(t, fmt.Sprintf(
		`[{"name":"s","prefix":"/s","upstream":%q}]`, upstream.URL)))
	defer front.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, front.URL+"/s", nil)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()

	br := bufio.NewReader(resp.Body)
	line, err := br.ReadString('\n')
	if err != nil {
		t.Fatalf("first chunk did not stream: %v", err)
	}
	if !strings.Contains(line, "one") {
		t.Fatalf("first line = %q, want it to contain one", line)
	}

	close(release)
	rest, _ := io.ReadAll(br)
	if !strings.Contains(string(rest), "two") {
		t.Fatalf("rest = %q, want it to contain two", rest)
	}
}
