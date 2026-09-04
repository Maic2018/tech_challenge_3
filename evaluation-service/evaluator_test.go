package main

import "testing"

func TestGetDeterministicBucket(t *testing.T) {
	inputs := []string{"user_42nova_ui", "user_1nova_ui", "", "qualquer-coisa"}
	for _, in := range inputs {
		b1 := getDeterministicBucket(in)
		b2 := getDeterministicBucket(in)
		if b1 != b2 {
			t.Fatalf("bucket não é determinístico para %q: %d != %d", in, b1, b2)
		}
		if b1 > 99 {
			t.Fatalf("bucket fora do intervalo 0-99 para %q: %d", in, b1)
		}
	}
}

func TestRunEvaluationLogic(t *testing.T) {
	app := &App{}
	enabled := &Flag{Name: "nova_ui", IsEnabled: true}
	disabled := &Flag{Name: "nova_ui", IsEnabled: false}

	percentageRule := func(value interface{}, ruleEnabled bool) *TargetingRule {
		return &TargetingRule{FlagName: "nova_ui", IsEnabled: ruleEnabled, Rules: Rule{Type: "PERCENTAGE", Value: value}}
	}

	cases := []struct {
		name string
		info *CombinedFlagInfo
		want bool
	}{
		{"flag inexistente retorna false", &CombinedFlagInfo{}, false},
		{"flag desabilitada retorna false", &CombinedFlagInfo{Flag: disabled}, false},
		{"flag habilitada sem regra retorna true", &CombinedFlagInfo{Flag: enabled}, true},
		{"regra desabilitada retorna true", &CombinedFlagInfo{Flag: enabled, Rule: percentageRule(0.0, false)}, true},
		{"percentual 100 libera para todos", &CombinedFlagInfo{Flag: enabled, Rule: percentageRule(100.0, true)}, true},
		{"percentual 0 bloqueia para todos", &CombinedFlagInfo{Flag: enabled, Rule: percentageRule(0.0, true)}, false},
		{"valor de percentual inválido retorna false", &CombinedFlagInfo{Flag: enabled, Rule: percentageRule("50", true)}, false},
		{"tipo de regra desconhecido retorna false", &CombinedFlagInfo{Flag: enabled, Rule: &TargetingRule{IsEnabled: true, Rules: Rule{Type: "USER_LIST"}}}, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := app.runEvaluationLogic(tc.info, "user_42"); got != tc.want {
				t.Fatalf("esperado %v, obtido %v", tc.want, got)
			}
		})
	}
}

func TestRunEvaluationLogic_PercentageIsStablePerUser(t *testing.T) {
	app := &App{}
	info := &CombinedFlagInfo{
		Flag: &Flag{Name: "nova_ui", IsEnabled: true},
		Rule: &TargetingRule{IsEnabled: true, Rules: Rule{Type: "PERCENTAGE", Value: 50.0}},
	}
	first := app.runEvaluationLogic(info, "user_42")
	for i := 0; i < 20; i++ {
		if app.runEvaluationLogic(info, "user_42") != first {
			t.Fatal("a decisão para o mesmo usuário deve ser estável entre chamadas")
		}
	}
}
