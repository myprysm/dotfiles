package main

import (
	"strings"
	"testing"
)

// Real traffic, measured from transcripts in the 2026-08-06 session: p50 179 B,
// p90 634 B, and only 0.07% of commands past 8 KB. These benchmarks measure the
// decision alone; process spawn adds 1.8 to 2.4 ms on the same machine and is
// paid by the shell floor too.
func BenchmarkTypical(b *testing.B) {
	SecretsDir = testSecretsDir
	cmds := []string{
		`git status --porcelain`,
		`cat README.md`,
		`go test ./... -run TestCorpus`,
		`git commit -m "document the .env loading order"`,
		`kubectl --kubeconfig ~/kubeconfig get pods`,
		`grep -n TODO Makefile`,
		`x=$(git rev-parse --short HEAD); echo "$x"`,
		`cat ~/.env`,
	}
	b.ReportAllocs()
	for i := 0; b.Loop(); i++ {
		decide(cmds[i%len(cmds)])
	}
}

func BenchmarkNoSecretNamed(b *testing.B) {
	SecretsDir = testSecretsDir
	const cmd = `git log --oneline -20 | head -5`
	b.ReportAllocs()
	for b.Loop() {
		decide(cmd)
	}
}

func BenchmarkLarge(b *testing.B) {
	SecretsDir = testSecretsDir
	cmd := "echo " + strings.Repeat("x", 100<<10)
	b.ReportAllocs()
	for b.Loop() {
		decide(cmd)
	}
}

// A word made of thousands of brace groups is exponential if expanded naively.
// It measured 8.7 s before maxBraceInput capped it; a filename is short, so a
// word this long is judged as written.
func BenchmarkBraceBomb(b *testing.B) {
	SecretsDir = testSecretsDir
	cmd := "cat ." + strings.Repeat("{e,f}", 50000)
	b.ReportAllocs()
	for b.Loop() {
		decide(cmd)
	}
}

// Many SHORT brace words is the shape the cap must NOT slow down, because each
// one is a plausible filename and every one is expanded.
func BenchmarkManyBraceWords(b *testing.B) {
	SecretsDir = testSecretsDir
	cmd := "cat " + strings.Repeat(".{e,f}nv ", 5000)
	b.ReportAllocs()
	for b.Loop() {
		decide(cmd)
	}
}

// A deeply nested command is the shape that overflowed the prototype's stack.
// It must reach a verdict or a recovered panic, never a hang.
func BenchmarkDeepNesting(b *testing.B) {
	SecretsDir = testSecretsDir
	cmd := strings.Repeat("$(", 2000) + "echo x" + strings.Repeat(")", 2000)
	b.ReportAllocs()
	for b.Loop() {
		decide(cmd)
	}
}
