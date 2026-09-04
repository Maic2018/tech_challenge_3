package main

import (
	"strings"
	"testing"
)

func TestHashAPIKey(t *testing.T) {
	// Vetor conhecido: sha256("abc")
	const want = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
	if got := hashAPIKey("abc"); got != want {
		t.Fatalf("hashAPIKey(\"abc\") = %s, esperado %s", got, want)
	}

	// Sempre 64 caracteres hexadecimais e determinístico
	h1 := hashAPIKey("tm_key_teste")
	h2 := hashAPIKey("tm_key_teste")
	if len(h1) != 64 {
		t.Fatalf("hash deveria ter 64 caracteres, tem %d", len(h1))
	}
	if h1 != h2 {
		t.Fatalf("hash não é determinístico: %s != %s", h1, h2)
	}
	if hashAPIKey("outra_chave") == h1 {
		t.Fatal("chaves diferentes não podem gerar o mesmo hash")
	}
}

func TestGenerateAPIKey(t *testing.T) {
	k1, err := generateAPIKey()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}
	k2, err := generateAPIKey()
	if err != nil {
		t.Fatalf("erro inesperado: %v", err)
	}

	if !strings.HasPrefix(k1, "tm_key_") {
		t.Fatalf("chave deveria começar com tm_key_: %s", k1)
	}
	// prefixo (7) + 32 bytes em hex (64)
	if len(k1) != 7+64 {
		t.Fatalf("tamanho inesperado da chave: %d", len(k1))
	}
	if k1 == k2 {
		t.Fatal("duas chaves geradas não podem ser iguais")
	}
}
