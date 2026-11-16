package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// Config is the Proxy configuration, read from a host-side JSON file and never
// mounted into the Sandbox.
type Config struct {
	Routes []Route `json:"routes"`
}

// Route maps a local path prefix to one upstream and the credentials to inject.
type Route struct {
	Name        string      `json:"name"`
	Prefix      string      `json:"prefix"`
	Upstream    string      `json:"upstream"`
	StripPrefix bool        `json:"strip_prefix"`
	Inject      []Injection `json:"inject"`
}

// Injection is one credential a Route adds to a forwarded request.
type Injection struct {
	In    string `json:"in"`    // "header" or "query"
	Name  string `json:"name"`  // header or parameter name
	Value string `json:"value"` // template, expanded from the host environment
}

// ResolveConfigPath returns the configuration path: the flag when given, else
// $XDG_CONFIG_HOME/asb/proxy.json, else ~/.config/asb/proxy.json.
func ResolveConfigPath(flag string) string {
	if flag != "" {
		return flag
	}
	dir := os.Getenv("XDG_CONFIG_HOME")
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil || home == "" {
			home = "."
		}
		dir = filepath.Join(home, ".config")
	}
	return filepath.Join(dir, "asb", "proxy.json")
}

// LoadConfig reads, validates, and expands a configuration file.
func LoadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read config: %w", err)
	}
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.DisallowUnknownFields()
	var cfg Config
	if err := dec.Decode(&cfg); err != nil {
		return nil, fmt.Errorf("parse config %s: %w", path, err)
	}
	// Report every problem in one pass rather than the first. Validation and
	// expansion are independent, so both run and their errors are joined.
	if err := errors.Join(cfg.validate(), cfg.expand(os.LookupEnv)); err != nil {
		return nil, fmt.Errorf("invalid config %s: %w", path, err)
	}
	return &cfg, nil
}

// validate collects every problem it finds, in route order, rather than
// returning on the first.
func (c *Config) validate() error {
	var errs []error
	seen := make(map[string]int, len(c.Routes))

	for i := range c.Routes {
		r := &c.Routes[i]

		switch {
		case r.Name == "":
			errs = append(errs, fmt.Errorf("routes[%d]: name is required", i))
		default:
			if prev, dup := seen[r.Name]; dup {
				errs = append(errs, fmt.Errorf("routes[%d]: duplicate route name %q (also routes[%d])", i, r.Name, prev))
			} else {
				seen[r.Name] = i
			}
		}

		if !strings.HasPrefix(r.Prefix, "/") {
			errs = append(errs, fmt.Errorf("route %q: prefix must start with /", r.Name))
		} else if strings.HasSuffix(r.Prefix, "/") && r.Prefix != "/" {
			errs = append(errs, fmt.Errorf("route %q: prefix must not end with /", r.Name))
		}

		if u, err := url.Parse(r.Upstream); err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
			errs = append(errs, fmt.Errorf("route %q: upstream must be an absolute http(s) URL", r.Name))
		}

		for j := range r.Inject {
			inj := &r.Inject[j]
			if inj.In != "header" && inj.In != "query" {
				errs = append(errs, fmt.Errorf("route %q: inject[%d].in must be header or query", r.Name, j))
			}
			if inj.Name == "" {
				errs = append(errs, fmt.Errorf("route %q: inject[%d].name is required", r.Name, j))
			}
			if inj.Value == "" {
				errs = append(errs, fmt.Errorf("route %q: inject[%d].value is required", r.Name, j))
			}
		}
	}

	return errors.Join(errs...)
}

// envRef matches a ${VAR} reference. A bare $ is left alone; only the braced
// form is expanded, so a value containing a literal dollar stays predictable.
var envRef = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)\}`)

// expand collects the expansion failure for every injection, so a config with
// several unset variables reports them all at once.
func (c *Config) expand(lookup func(string) (string, bool)) error {
	var errs []error
	for i := range c.Routes {
		r := &c.Routes[i]
		for j := range r.Inject {
			v, err := expandEnv(r.Inject[j].Value, lookup)
			if err != nil {
				errs = append(errs, fmt.Errorf("route %q: inject[%d].value: %w", r.Name, j, err))
				continue
			}
			r.Inject[j].Value = v
		}
	}
	return errors.Join(errs...)
}

// expandEnv expands ${VAR} references, failing on the first unset variable so a
// missing secret is an error and never an empty string.
func expandEnv(s string, lookup func(string) (string, bool)) (string, error) {
	var firstErr error
	out := envRef.ReplaceAllStringFunc(s, func(m string) string {
		name := m[2 : len(m)-1]
		val, ok := lookup(name)
		if !ok {
			if firstErr == nil {
				firstErr = fmt.Errorf("environment variable %s is not set", name)
			}
			return m
		}
		return val
	})
	return out, firstErr
}
