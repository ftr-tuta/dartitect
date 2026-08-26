# Dartitect Geometry

[English](README.md)

## Objetivo e contrato numérico

`dartitect_geometry` fornece pontos cartesianos 2D finitos, polígonos imutáveis
validados com holes e subdivisão determinística do polo de inacessibilidade.
Coordenadas são planas e as unidades acompanham o input.

`defaultGeometryTolerance` é o bound absoluto e explícito de `1e-12`. Ele é
usado em comparações de boundary na unidade das coordenadas e em determinantes
de área/orientação na unidade do input ao quadrado. Igualdade de pontos continua
exata. `precision` usa a unidade do input, deve ser finita/positiva e limita a
melhoria de distância ainda possível quando a subdivisão para; o default é `1`.

## Contrato do boundary

- Razão do package: isolar algoritmos planares opcionais e atribuição do core.
- Owns: cópias imutáveis das coordenadas; não borrows nem persists nada.
- Logs: nada; coordenadas e resultados nunca entram em telemetria.
- Supports: pontos 2D finitos, ring externo simples, holes sem sobreposição,
  polylabel determinístico, tolerância e precisão explícitas.
- Does not support: GIS, CRS, projeção, geodesia, latitude/longitude especial,
  antimeridiano, conversão de unidades ou reparo topológico.
- Remoção: remova o package e substitua chamadas no adapter de geometry; nenhum
  formato persistido ou recurso runtime exige migração.

## Atribuição

A subdivisão deriva do Mapbox polylabel. A atribuição ISC está preservada em
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
