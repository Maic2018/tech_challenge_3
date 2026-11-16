package main

import "testing"

func TestChaosShouldFailRespeitaATaxa(t *testing.T) {
	for _, rate := range []uint64{0, 5, 30, 50, 100} {
		c := &chaosState{}
		c.errorRate.Store(rate)
		falhas := 0
		for i := 0; i < 100; i++ {
			if c.shouldFail() {
				falhas++
			}
		}
		if uint64(falhas) != rate {
			t.Fatalf("error_rate=%d: esperado %d falhas em 100, obtido %d", rate, rate, falhas)
		}
	}
}

func TestChaosShouldFailIntercalaAsFalhas(t *testing.T) {
	c := &chaosState{}
	c.errorRate.Store(50)
	seguidas := 0
	for i := 0; i < 10; i++ {
		if c.shouldFail() {
			seguidas++
			if seguidas > 1 {
				t.Fatal("com error_rate=50 não deveria haver duas falhas seguidas")
			}
		} else {
			seguidas = 0
		}
	}
}
