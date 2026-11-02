# Quickstart — Mensagens cifradas entre as apps (motorista)

Validação em `Prototipo/driver/`. O ponta a ponta exige a feature irmã do passageiro; sem ela, os
automatizados e a sonda local bastam para o lado do motorista.

## Automatizados

```bash
flutter analyze        # "No issues found!"
flutter test test/services/nip44_test.dart            # vetores oficiais do NIP-44
flutter test test/services/message_cipher_test.dart
flutter test test/services/identity_service_test.dart
flutter test test/screens/map_screen_test.dart
flutter test           # suíte completa
```

## Medições (SC-004, SC-005)

```bash
dart run tool/probe_cipher_size.dart
```

**Esperado**: tempo por mensagem (após o 1º ECDH) bem abaixo de 100 ms; o `20011` cifrado de 1000
pontos fica abaixo de 50 % de 131 072 B. Registrar os valores em `research.md` D6.

## Cenários manuais (dois aparelhos, relay em comum, as duas apps atualizadas)

1. **Orçamento cifrado (US1)**: enviar um orçamento; num cliente Nostr qualquer, o `content` do
   `kind: 20002` é uma string base64 opaca; o passageiro o exibe normalmente.
2. **Localização/rota/chegada cifradas (US1)**: durante a corrida, `20005`, `20007`, `20009`,
   `20011` aparecem opacos; mapa, modais e rota do passageiro funcionam como antes (FR-011).
3. **Recepção do motorista (US2)**: passageiro aceita, confirma encontro e destino; o motorista
   percorre "Orçamento aceito" → "Em corrida" → avaliação como antes.
4. **Descarte silencioso (US2)**: publicar à mão um `20008` em claro (ou cifrado a outra chave)
   referenciando a corrida ativa; nada acontece, nenhum erro aparece.
5. **Exceção do 20001 (US3)**: a solicitação continua legível no relay (esperado e documentado).
