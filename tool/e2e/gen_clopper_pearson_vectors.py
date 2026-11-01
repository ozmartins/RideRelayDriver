#!/usr/bin/env python3
"""Gera test/fixtures/e2e_clopper_pearson_vectors.json com scipy (segunda via, D5).

Uso:  python3 -I tool/e2e/gen_clopper_pearson_vectors.py

Não faz parte do roteiro nem do app: serve só para conferir a implementação em
Dart (tool/e2e/src/estatistica.dart) contra uma referência independente.
Falha se o scipy não existir, em vez de inventar valores.
"""
import json
import pathlib
import sys

try:
    import scipy
    from scipy.stats import beta
except ImportError:
    sys.exit("scipy não encontrado: não é possível gerar a referência independente.")

CONFIANCA = 0.95
TAMANHOS = [1, 2, 3, 5, 10, 20, 30, 40, 60, 80]


def intervalo(x: int, n: int):
    alfa = 1 - CONFIANCA
    inferior = 0.0 if x == 0 else float(beta.ppf(alfa / 2, x, n - x + 1))
    superior = 1.0 if x == n else float(beta.ppf(1 - alfa / 2, x + 1, n - x))
    return inferior, superior


casos = []
for n in TAMANHOS:
    for x in range(n + 1):
        inf, sup = intervalo(x, n)
        casos.append({"x": x, "n": n, "inferior": inf, "superior": sup})

saida = pathlib.Path(__file__).resolve().parents[2] / "test" / "fixtures" / "e2e_clopper_pearson_vectors.json"
saida.write_text(
    json.dumps(
        {
            "gerado_com": f"scipy {scipy.__version__}",
            "comando": "python3 -I tool/e2e/gen_clopper_pearson_vectors.py",
            "confianca": CONFIANCA,
            "casos": casos,
        },
        indent=1,
    )
    + "\n"
)
print(f"{len(casos)} casos gravados em {saida}")
