package main

import (
	"encoding/json"
	"log"
	"net/http"
	"sync/atomic"
)

// Injeção de falhas para a demonstração de alerta + self-healing (Fase 4).
// O estado fica só na memória do pod: um "kubectl rollout restart" (ação do
// self-healing) sobe pods novos e a falha desaparece, como num vazamento de
// recurso real que se resolve com restart.
type chaosState struct {
	errorRate atomic.Uint64 // 0-100: % das requisições que devolvem HTTP 500
	counter   atomic.Uint64
}

type chaosRequest struct {
	ErrorRate uint64 `json:"error_rate"`
}

// shouldFail distribui as falhas de forma determinística e uniforme: com
// error_rate=30, 30 de cada 100 requisições falham, intercaladas com as que passam
// (sem gerador aleatório).
func (c *chaosState) shouldFail() bool {
	rate := c.errorRate.Load()
	if rate == 0 {
		return false
	}
	return (c.counter.Add(1)*rate)%100 < rate
}

// chaosMiddleware devolve 500 em parte das requisições enquanto a falha estiver ativa.
// /health e /admin/* ficam de fora para o pod continuar "saudável" para o kubelet —
// a falha é silenciosa, só aparece nas métricas, logs e traces.
func (a *App) chaosMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/validate" && a.Chaos.shouldFail() {
			log.Printf("trace_id=%s ERRO falha injetada (chaos) em %s: respondendo 500", traceID(r.Context()), r.URL.Path)
			http.Error(w, "Erro interno (falha injetada)", http.StatusInternalServerError)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// chaosHandler: GET mostra o estado; POST {"error_rate": 0-100} ativa/desativa a falha.
// Protegido pela MASTER_KEY (masterKeyAuthMiddleware).
func (a *App) chaosHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
	case http.MethodPost:
		var req chaosRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.ErrorRate > 100 {
			http.Error(w, "Corpo inválido: use {\"error_rate\": 0-100}", http.StatusBadRequest)
			return
		}
		a.Chaos.errorRate.Store(req.ErrorRate)
		log.Printf("trace_id=%s Chaos: error_rate de /validate ajustado para %d%%", traceID(r.Context()), req.ErrorRate)
	default:
		http.Error(w, "Método não permitido", http.StatusMethodNotAllowed)
		return
	}
	writeJSON(w, http.StatusOK, map[string]uint64{"error_rate": a.Chaos.errorRate.Load()})
}
