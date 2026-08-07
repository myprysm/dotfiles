package main

import (
	"bufio"
	"encoding/json"
	"os"
	"strings"
	"testing"
)

// The corpus is the adversarial record: 146 probes lifted from
// tests/test-block-secret-reads.sh and 59 hand-written attacks. Every case
// encodes a finding from a real review, so a case is not deleted without
// deciding to.
//
// Paths carry the placeholder /Users/OPERATOR: usernames are infrastructure
// identifiers and this repository is public.
type corpusCase struct {
	Expect string `json:"expect"`
	Why    string `json:"why"`
	Cmd    string `json:"cmd"`
	Source string `json:"source"`
}

func loadCorpus(t *testing.T) []corpusCase {
	t.Helper()
	f, err := os.Open("testdata/corpus.jsonl")
	if err != nil {
		t.Fatalf("corpus: %v", err)
	}
	defer f.Close()
	var out []corpusCase
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 1<<20), 1<<20)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" {
			continue
		}
		var c corpusCase
		if err := json.Unmarshal([]byte(line), &c); err != nil {
			t.Fatalf("corpus line %q: %v", line, err)
		}
		out = append(out, c)
	}
	if err := sc.Err(); err != nil {
		t.Fatalf("corpus: %v", err)
	}
	return out
}

// verdictOf renders a decision as the word the probes are written in.
//
// "undecided" is its own answer since round 6: a command neither dialect can
// parse and whose text names nothing dangerous is handed to the shell floor
// rather than refused, so a probe that expects one must not be able to pass by
// receiving the other. See decide().
func verdictOf(src string) string {
	switch cat, _ := decide(src); cat {
	case catNone:
		return "allow"
	case catUndecided:
		return "undecided"
	}
	return "deny"
}

func TestCorpus(t *testing.T) {
	SecretsDir = "/Users/OPERATOR/.local/share/6f2a1c94-8d3e-4b7a-9f10-2c5e8a7b3d61"
	cases := loadCorpus(t)
	var falseAllow, falseDeny int
	for _, c := range cases {
		got := verdictOf(c.Cmd)
		if got == c.Expect {
			continue
		}
		if c.Expect == "deny" {
			falseAllow++
			t.Errorf("FALSE NEGATIVE [%s] %q\n  want deny (%s), got allow", c.Source, c.Cmd, c.Why)
		} else {
			falseDeny++
			t.Errorf("FALSE POSITIVE [%s] %q\n  want allow (%s), got deny", c.Source, c.Cmd, c.Why)
		}
	}
	t.Logf("corpus: %d cases, %d false negatives, %d false positives", len(cases), falseAllow, falseDeny)
}
