package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeConfig(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "proxy.json")
	if err := os.WriteFile(p, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

func TestLoadConfigExpandsEnv(t *testing.T) {
	t.Setenv("TOKEN", "secret")
	p := writeConfig(t, `{"routes":[{"name":"openai","prefix":"/openai","upstream":"https://api.example.com","strip_prefix":true,"inject":[{"in":"header","name":"Authorization","value":"Bearer ${TOKEN}"}]}]}`)

	cfg, err := LoadConfig(p)
	if err != nil {
		t.Fatal(err)
	}
	if got := cfg.Routes[0].Inject[0].Value; got != "Bearer secret" {
		t.Fatalf("expanded value = %q, want %q", got, "Bearer secret")
	}
}

func TestLoadConfigUnsetVarFails(t *testing.T) {
	os.Unsetenv("ASB_PROXY_TEST_MISSING")
	p := writeConfig(t, `{"routes":[{"name":"a","prefix":"/a","upstream":"https://x.example.com","inject":[{"in":"header","name":"A","value":"${ASB_PROXY_TEST_MISSING}"}]}]}`)

	_, err := LoadConfig(p)
	if err == nil || !strings.Contains(err.Error(), "ASB_PROXY_TEST_MISSING") {
		t.Fatalf("want error naming the variable, got %v", err)
	}
}

func TestLoadConfigValidation(t *testing.T) {
	cases := map[string]string{
		"duplicate name": `{"routes":[
			{"name":"a","prefix":"/a","upstream":"https://x.example.com"},
			{"name":"a","prefix":"/b","upstream":"https://x.example.com"}]}`,
		"prefix without slash":  `{"routes":[{"name":"a","prefix":"a","upstream":"https://x.example.com"}]}`,
		"prefix trailing slash": `{"routes":[{"name":"a","prefix":"/a/","upstream":"https://x.example.com"}]}`,
		"relative upstream":     `{"routes":[{"name":"a","prefix":"/a","upstream":"x.example.com"}]}`,
		"unknown field":         `{"routes":[{"name":"a","prefix":"/a","upstream":"https://x.example.com","typo":1}]}`,
		"bad inject kind":       `{"routes":[{"name":"a","prefix":"/a","upstream":"https://x.example.com","inject":[{"in":"cookie","name":"A","value":"v"}]}]}`,
		"empty inject name":     `{"routes":[{"name":"a","prefix":"/a","upstream":"https://x.example.com","inject":[{"in":"header","name":"","value":"v"}]}]}`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := LoadConfig(writeConfig(t, body)); err == nil {
				t.Fatal("want an error, got nil")
			}
		})
	}
}

func TestLoadConfigReportsAllErrors(t *testing.T) {
	// A bad prefix, a duplicate name, and a relative upstream in one file.
	p := writeConfig(t, `{"routes":[
		{"name":"a","prefix":"nope","upstream":"x.example.com"},
		{"name":"a","prefix":"/b"}]}`)

	_, err := LoadConfig(p)
	if err == nil {
		t.Fatal("want an error, got nil")
	}
	for _, want := range []string{
		"prefix must start with /",
		"duplicate route name",
		"upstream must be an absolute",
	} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error missing %q:\n%s", want, err)
		}
	}
}

func TestLoadConfigReportsAllUnsetVars(t *testing.T) {
	os.Unsetenv("ASB_PROXY_TEST_MISSING_A")
	os.Unsetenv("ASB_PROXY_TEST_MISSING_B")
	p := writeConfig(t, `{"routes":[{"name":"a","prefix":"/a","upstream":"https://x.example.com","inject":[
		{"in":"header","name":"A","value":"${ASB_PROXY_TEST_MISSING_A}"},
		{"in":"header","name":"B","value":"${ASB_PROXY_TEST_MISSING_B}"}]}]}`)

	_, err := LoadConfig(p)
	if err == nil {
		t.Fatal("want an error, got nil")
	}
	for _, want := range []string{"ASB_PROXY_TEST_MISSING_A", "ASB_PROXY_TEST_MISSING_B"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error missing %q:\n%s", want, err)
		}
	}
}

func TestResolveConfigPath(t *testing.T) {
	t.Setenv("XDG_CONFIG_HOME", "/xdg")

	if got, want := ResolveConfigPath(""), filepath.Join("/xdg", "asb", "proxy.json"); got != want {
		t.Fatalf("default path = %q, want %q", got, want)
	}
	if got, want := ResolveConfigPath("flag.json"), "flag.json"; got != want {
		t.Fatalf("flag path = %q, want %q", got, want)
	}
}
