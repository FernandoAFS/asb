package main

import (
	"errors"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strings"
	"time"
)

// routeRuntime is one Route with its parsed upstream and prepared reverse proxy.
type routeRuntime struct {
	route    Route
	upstream *url.URL
	proxy    *httputil.ReverseProxy
}

// proxyHandler routes a request to the longest matching Route and forwards it.
type proxyHandler struct {
	routes []*routeRuntime
	logger *log.Logger
}

func newProxyHandler(cfg *Config, logger *log.Logger) (*proxyHandler, error) {
	h := &proxyHandler{logger: logger}

	transport := &http.Transport{
		// Dial timeout only; no overall response deadline, because responses
		// stream (SSE and streamable-HTTP MCP must not be cut off).
		DialContext:       (&net.Dialer{Timeout: 30 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		ForceAttemptHTTP2: true,
	}

	for i := range cfg.Routes {
		r := cfg.Routes[i]
		u, err := url.Parse(r.Upstream)
		if err != nil {
			return nil, err
		}
		rt := &routeRuntime{route: r, upstream: u}
		rt.proxy = &httputil.ReverseProxy{
			Transport: transport,
			// Flush every write so streamed responses reach the client at once.
			FlushInterval: -1,
			Rewrite: func(pr *httputil.ProxyRequest) {
				rewrite(pr, rt)
			},
			ErrorHandler: func(w http.ResponseWriter, req *http.Request, err error) {
				status := http.StatusBadGateway
				var ne net.Error
				if errors.As(err, &ne) && ne.Timeout() {
					status = http.StatusGatewayTimeout
				}
				if h.logger != nil {
					h.logger.Printf("%s %s -> %s: %v", req.Method, req.URL.Path, rt.route.Name, err)
				}
				http.Error(w, http.StatusText(status), status)
			},
		}
		h.routes = append(h.routes, rt)
	}
	return h, nil
}

// rewrite points the outbound request at the Route's upstream, strips the
// prefix when configured, and applies the Route's injections. An injected
// header or parameter replaces any inbound value of the same name.
func rewrite(pr *httputil.ProxyRequest, rt *routeRuntime) {
	out := pr.Out

	path := pr.In.URL.Path
	if rt.route.StripPrefix {
		path = strings.TrimPrefix(path, rt.route.Prefix)
		if path == "" {
			path = "/"
		}
		if !strings.HasPrefix(path, "/") {
			path = "/" + path
		}
	}

	out.URL.Scheme = rt.upstream.Scheme
	out.URL.Host = rt.upstream.Host
	out.URL.Path = joinURLPath(rt.upstream.Path, path)
	out.URL.RawPath = ""
	out.Host = rt.upstream.Host

	for _, inj := range rt.route.Inject {
		if inj.In == "header" {
			out.Header.Set(inj.Name, inj.Value)
		}
	}

	query := out.URL.Query()
	for _, inj := range rt.route.Inject {
		if inj.In == "query" {
			query.Set(inj.Name, inj.Value)
		}
	}
	out.URL.RawQuery = query.Encode()
}

// joinURLPath joins an upstream base path with the rewritten request path.
func joinURLPath(a, b string) string {
	switch {
	case strings.HasSuffix(a, "/") && strings.HasPrefix(b, "/"):
		return a + b[1:]
	case !strings.HasSuffix(a, "/") && !strings.HasPrefix(b, "/"):
		return a + "/" + b
	default:
		return a + b
	}
}

// match returns the Route with the longest prefix the path falls under, or nil.
func (h *proxyHandler) match(path string) *routeRuntime {
	var best *routeRuntime
	for _, rt := range h.routes {
		if !prefixMatch(rt.route.Prefix, path) {
			continue
		}
		if best == nil || len(rt.route.Prefix) > len(best.route.Prefix) {
			best = rt
		}
	}
	return best
}

func prefixMatch(prefix, path string) bool {
	if prefix == "/" {
		return true
	}
	return path == prefix || strings.HasPrefix(path, prefix+"/")
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (s *statusRecorder) WriteHeader(code int) {
	s.status = code
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Flush() {
	if f, ok := s.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (h *proxyHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	rt := h.match(r.URL.Path)
	if rt == nil {
		if h.logger != nil {
			h.logger.Printf("%s %s -> 404", r.Method, r.URL.Path)
		}
		http.NotFound(w, r)
		return
	}
	rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
	rt.proxy.ServeHTTP(rec, r)
	if h.logger != nil {
		h.logger.Printf("%s %s -> %s %d", r.Method, r.URL.Path, rt.route.Name, rec.status)
	}
}
