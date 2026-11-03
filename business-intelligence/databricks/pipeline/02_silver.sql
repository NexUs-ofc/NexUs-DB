-- 02 · Silver: limpeza e padronização da Bronze -> workspace.silver
-- Arquivo-fonte do ETL pipeline Pipeline_silver_gold. Documentação: databricks/pipeline/README.md
--
-- Regras gerais:
--   * Dimensões e fato_movimento usam a foto MAIS RECENTE da Bronze (cadastro atual / histórico completo).
--   * fato_estoque e fato_estoque_minimo usam TODAS as fotos (histórico diário do estado da despensa).
--   * Duplicatas: ROW_NUMBER por chave (+ data de referência), fica a gravação mais recente.
--   * Datas AAAAMMDD viram DATE; -1 vira NULL.
--   * Chave sem correspondência na dimensão do mesmo dia (órfã) vira -1 ("Não informado").
--   * Expectations: ON VIOLATION DROP ROW descarta a linha; sem ON VIOLATION só registra o alerta.

-- ===================================================================== REFERÊNCIA
-- 27 UFs com região e coordenadas da capital (o mapa usa a UF; lat/long de endereço não é trazida)
CREATE OR REFRESH MATERIALIZED VIEW workspace.silver.ref_uf
COMMENT 'Tabela fixa das 27 UFs: nome, região, capital e coordenadas da capital (para o mapa)'
AS SELECT * FROM VALUES
  ('AC','Acre','Norte','Rio Branco',-9.9750,-67.8243),
  ('AL','Alagoas','Nordeste','Maceió',-9.6660,-35.7350),
  ('AP','Amapá','Norte','Macapá',0.0349,-51.0694),
  ('AM','Amazonas','Norte','Manaus',-3.1190,-60.0217),
  ('BA','Bahia','Nordeste','Salvador',-12.9711,-38.5108),
  ('CE','Ceará','Nordeste','Fortaleza',-3.7172,-38.5434),
  ('DF','Distrito Federal','Centro-Oeste','Brasília',-15.7801,-47.9292),
  ('ES','Espírito Santo','Sudeste','Vitória',-20.3155,-40.3128),
  ('GO','Goiás','Centro-Oeste','Goiânia',-16.6869,-49.2648),
  ('MA','Maranhão','Nordeste','São Luís',-2.5307,-44.3068),
  ('MT','Mato Grosso','Centro-Oeste','Cuiabá',-15.6010,-56.0974),
  ('MS','Mato Grosso do Sul','Centro-Oeste','Campo Grande',-20.4428,-54.6464),
  ('MG','Minas Gerais','Sudeste','Belo Horizonte',-19.9167,-43.9345),
  ('PA','Pará','Norte','Belém',-1.4550,-48.5024),
  ('PB','Paraíba','Nordeste','João Pessoa',-7.1153,-34.8610),
  ('PR','Paraná','Sul','Curitiba',-25.4284,-49.2733),
  ('PE','Pernambuco','Nordeste','Recife',-8.0476,-34.8770),
  ('PI','Piauí','Nordeste','Teresina',-5.0892,-42.8016),
  ('RJ','Rio de Janeiro','Sudeste','Rio de Janeiro',-22.9068,-43.1729),
  ('RN','Rio Grande do Norte','Nordeste','Natal',-5.7945,-35.2110),
  ('RS','Rio Grande do Sul','Sul','Porto Alegre',-30.0346,-51.2177),
  ('RO','Rondônia','Norte','Porto Velho',-8.7608,-63.8999),
  ('RR','Roraima','Norte','Boa Vista',2.8238,-60.6753),
  ('SC','Santa Catarina','Sul','Florianópolis',-27.5954,-48.5480),
  ('SP','São Paulo','Sudeste','São Paulo',-23.5505,-46.6333),
  ('SE','Sergipe','Nordeste','Aracaju',-10.9472,-37.0731),
  ('TO','Tocantins','Norte','Palmas',-10.2491,-48.3243)
AS t(uf, nome_uf, regiao, capital, latitude, longitude);

-- ===================================================================== DIMENSÕES
CREATE OR REFRESH MATERIALIZED VIEW workspace.silver.dim_alimento (
  CONSTRAINT sk_alimento_preenchida EXPECT (sk_alimento IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT alimento_com_nome      EXPECT (alimento IS NOT NULL)
)
COMMENT 'Alimentos (foto mais recente), textos padronizados, + linha -1 Não informado'
AS
WITH ultimo AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY sk_alimento ORDER BY _ingerido_em DESC) AS rn
  FROM workspace.bronze.dim_alimento
  WHERE _data_referencia = (SELECT MAX(_data_referencia) FROM workspace.bronze.dim_alimento)
)
SELECT sk_alimento,
       NULLIF(TRIM(alimento), '')                              AS alimento,
       COALESCE(NULLIF(TRIM(marca), ''), 'Sem marca')           AS marca,
       CAST(embalagem AS DECIMAL(12,3))                         AS embalagem,
       UPPER(TRIM(unidade))                                     AS unidade,
       TRIM(descricao)                                          AS descricao,
       COALESCE(NULLIF(TRIM(categoria), ''), 'Não informada')   AS categoria
FROM ultimo WHERE rn = 1
UNION ALL
SELECT -1, 'Não informado', 'Sem marca', NULL, NULL, 'Não informado', 'Não informada';

CREATE OR REFRESH MATERIALIZED VIEW workspace.silver.dim_localidade (
  CONSTRAINT sk_localidade_preenchida EXPECT (sk_localidade IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT uf_valida                EXPECT (uf <> 'N/I' OR sk_localidade = -1)
)
COMMENT 'Cidades (foto mais recente), UF validada contra ref_uf, coordenadas da capital, + linha -1'
AS
WITH ultimo AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY sk_localidade ORDER BY _ingerido_em DESC) AS rn
  FROM workspace.bronze.dim_localidade
  WHERE _data_referencia = (SELECT MAX(_data_referencia) FROM workspace.bronze.dim_localidade)
)
SELECT l.sk_localidade,
       COALESCE(NULLIF(TRIM(l.cidade), ''), 'Não informada') AS cidade,
       COALESCE(r.uf, 'N/I')          AS uf,
       COALESCE(r.nome_uf, 'Não informada') AS nome_uf,
       COALESCE(r.regiao, 'N/I')      AS regiao,
       r.latitude                     AS latitude_uf,
       r.longitude                    AS longitude_uf
FROM ultimo l
LEFT JOIN workspace.silver.ref_uf r ON r.uf = UPPER(TRIM(l.uf))
WHERE l.rn = 1
UNION ALL
SELECT -1, 'Não informada', 'N/I', 'Não informada', 'N/I', NULL, NULL;

CREATE OR REFRESH MATERIALIZED VIEW workspace.silver.dim_perfil (
  CONSTRAINT sk_perfil_preenchida EXPECT (sk_perfil IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT tipo_conhecido       EXPECT (tipo IN ('HOUSEHOLD', 'COMPANY', 'STORE', 'ADMIN', 'N/I')),
  CONSTRAINT origem_conhecida     EXPECT (origem IN ('APP', 'SIMULADO_BI', 'N/I'))
)
COMMENT 'Perfis (foto mais recente), textos padronizados, + linha -1'
AS
WITH ultimo AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY sk_perfil ORDER BY _ingerido_em DESC) AS rn
  FROM workspace.bronze.dim_perfil
  WHERE _data_referencia = (SELECT MAX(_data_referencia) FROM workspace.bronze.dim_perfil)
)
SELECT sk_perfil,
       UPPER(TRIM(tipo))                                AS tipo,
       UPPER(TRIM(status))                              AS status,
       COALESCE(UPPER(TRIM(login)), 'NAO_INFORMADO')    AS login,
       ano_mes_cadastro,
       tempo_de_casa,
       UPPER(TRIM(origem))                              AS origem
FROM ultimo WHERE rn = 1
UNION ALL
SELECT -1, 'N/I', 'N/I', 'NAO_INFORMADO', NULL, NULL, 'N/I';

-- ===================================================================== FATOS
-- Estado da despensa: TODAS as fotos diárias. dias_ate_vencer e status_validade são
-- recalculados com a data da foto (data_referencia), não com o "hoje" do Neon.
CREATE OR REFRESH MATERIALIZED VIEW workspace.silver.fato_estoque (
  CONSTRAINT id_item_preenchido    EXPECT (id_item IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT data_entrada_valida   EXPECT (data_entrada IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT quantidade_positiva   EXPECT (quantidade > 0),
  CONSTRAINT validade_apos_entrada EXPECT (data_validade IS NULL OR vida_util_dias >= 0)
)
COMMENT '1 linha = 1 lote na despensa em cada foto diária (data_referencia)'
AS
WITH b AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY _data_referencia, id_item ORDER BY _ingerido_em DESC) AS rn
  FROM workspace.bronze.fato_estoque
),
d AS (
  SELECT *,
         try_to_date(CAST(NULLIF(sk_data_entrada, -1)  AS STRING), 'yyyyMMdd') AS data_entrada,
         try_to_date(CAST(NULLIF(sk_data_validade, -1) AS STRING), 'yyyyMMdd') AS data_validade
  FROM b WHERE rn = 1
)
SELECT d._data_referencia                                   AS data_referencia,
       d.id_item,
       CASE WHEN a.sk_alimento   IS NULL THEN -1 ELSE d.sk_alimento   END AS sk_alimento,
       CASE WHEN p.sk_perfil     IS NULL THEN -1 ELSE d.sk_perfil     END AS sk_perfil,
       CASE WHEN l.sk_localidade IS NULL THEN -1 ELSE d.sk_localidade END AS sk_localidade,
       d.data_entrada,
       d.data_validade,
       CAST(d.quantidade AS INT)                            AS quantidade,
       CAST(d.data_validade IS NOT NULL AS INT)             AS tem_validade,
       DATEDIFF(d.data_validade, d._data_referencia)        AS dias_ate_vencer,
       DATEDIFF(d.data_validade, d.data_entrada)            AS vida_util_dias,
       CASE WHEN d.data_validade IS NULL                              THEN 'SEM_VALIDADE'
            WHEN d.data_validade <  d._data_referencia                THEN 'VENCIDO'
            WHEN d.data_validade <= date_add(d._data_referencia, 7)   THEN 'VENCE_7D'
            WHEN d.data_validade <= date_add(d._data_referencia, 30)  THEN 'VENCE_30D'
            ELSE 'OK' END                                   AS status_validade
FROM d
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_alimento   FROM workspace.bronze.dim_alimento)   a
       ON a._data_referencia = d._data_referencia AND a.sk_alimento = d.sk_alimento
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_perfil     FROM workspace.bronze.dim_perfil)     p
       ON p._data_referencia = d._data_referencia AND p.sk_perfil = d.sk_perfil
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_localidade FROM workspace.bronze.dim_localidade) l
       ON l._data_referencia = d._data_referencia AND l.sk_localidade = d.sk_localidade;

-- Eventos (consumo/descarte): cada foto já traz o histórico inteiro e eventos não mudam,
-- então basta a foto mais recente (evita multiplicar o histórico pelo nº de dias).
CREATE OR REFRESH MATERIALIZED VIEW workspace.silver.fato_movimento (
  CONSTRAINT id_movimento_preenchido EXPECT (id_movimento IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT tipo_evento_valido      EXPECT (tipo_evento IN ('DISCARDED', 'CONSUMED')) ON VIOLATION DROP ROW,
  CONSTRAINT data_evento_valida      EXPECT (data_evento IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT evento_apos_compra      EXPECT (dias_em_casa >= 0),
  CONSTRAINT quantidade_positiva     EXPECT (qtd_consumida + qtd_descartada > 0)
)
COMMENT '1 linha = 1 lote consumido ou descartado vencido (histórico de bi_hist.registro_estoque)'
AS
WITH b AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY id_movimento ORDER BY _ingerido_em DESC) AS rn
  FROM workspace.bronze.fato_movimento
  WHERE _data_referencia = (SELECT MAX(_data_referencia) FROM workspace.bronze.fato_movimento)
),
d AS (
  SELECT *,
         try_to_date(CAST(NULLIF(sk_data_evento, -1)   AS STRING), 'yyyyMMdd') AS data_evento,
         try_to_date(CAST(NULLIF(sk_data_compra, -1)   AS STRING), 'yyyyMMdd') AS data_compra,
         try_to_date(CAST(NULLIF(sk_data_validade, -1) AS STRING), 'yyyyMMdd') AS data_validade,
         -- V11 trocou item_consumed/item_expired por CONSUMED/DISCARDED: aceita os dois
         CASE UPPER(TRIM(tipo_evento))
              WHEN 'CONSUMED'      THEN 'CONSUMED' WHEN 'ITEM_CONSUMED' THEN 'CONSUMED'
              WHEN 'DISCARDED'     THEN 'DISCARDED' WHEN 'ITEM_EXPIRED' THEN 'DISCARDED'
         END AS tipo_evento_limpo
  FROM b WHERE rn = 1
)
SELECT d.id_movimento,
       CASE WHEN a.sk_alimento   IS NULL THEN -1 ELSE d.sk_alimento   END AS sk_alimento,
       CASE WHEN p.sk_perfil     IS NULL THEN -1 ELSE d.sk_perfil     END AS sk_perfil,
       CASE WHEN l.sk_localidade IS NULL THEN -1 ELSE d.sk_localidade END AS sk_localidade,
       d.data_evento,
       date_format(d.data_evento, 'yyyy-MM')                  AS ano_mes_evento,
       d.data_compra,
       d.data_validade,
       d.tipo_evento_limpo                                    AS tipo_evento,
       CAST(d.tipo_evento_limpo = 'DISCARDED' AS INT)         AS expirado,   -- = descartado
       CAST(d.tipo_evento_limpo = 'CONSUMED'  AS INT)         AS consumido,
       COALESCE(CAST(d.qtd_consumida  AS INT), 0)             AS qtd_consumida,
       COALESCE(CAST(d.qtd_descartada AS INT), 0)             AS qtd_descartada,
       DATEDIFF(d.data_evento, d.data_compra)                 AS dias_em_casa,
       d._data_referencia                                     AS data_referencia
FROM d
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_alimento   FROM workspace.bronze.dim_alimento)   a
       ON a._data_referencia = d._data_referencia AND a.sk_alimento = d.sk_alimento
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_perfil     FROM workspace.bronze.dim_perfil)     p
       ON p._data_referencia = d._data_referencia AND p.sk_perfil = d.sk_perfil
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_localidade FROM workspace.bronze.dim_localidade) l
       ON l._data_referencia = d._data_referencia AND l.sk_localidade = d.sk_localidade;

-- Estoque mínimo: TODAS as fotos (histórico diário do D6). abaixo_minimo é recalculado.
CREATE OR REFRESH MATERIALIZED VIEW workspace.silver.fato_estoque_minimo (
  CONSTRAINT chave_preenchida     EXPECT (sk_perfil IS NOT NULL AND sk_alimento IS NOT NULL) ON VIOLATION DROP ROW,
  CONSTRAINT minimo_positivo      EXPECT (minimo > 0) ON VIOLATION DROP ROW,
  CONSTRAINT estoque_nao_negativo EXPECT (estoque >= 0)
)
COMMENT '1 linha = 1 household x alimento com mínimo > 0, em cada foto diária (estoque sem lotes vencidos)'
AS
WITH b AS (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY _data_referencia, sk_perfil, sk_alimento ORDER BY _ingerido_em DESC) AS rn
  FROM workspace.bronze.fato_estoque_minimo
)
SELECT b._data_referencia                                         AS data_referencia,
       CASE WHEN p.sk_perfil     IS NULL THEN -1 ELSE b.sk_perfil     END AS sk_perfil,
       CASE WHEN a.sk_alimento   IS NULL THEN -1 ELSE b.sk_alimento   END AS sk_alimento,
       CASE WHEN l.sk_localidade IS NULL THEN -1 ELSE b.sk_localidade END AS sk_localidade,
       CAST(b.estoque AS INT)                                     AS estoque,
       CAST(b.minimo  AS INT)                                     AS minimo,
       CAST(COALESCE(b.estoque, 0) < b.minimo AS INT)             AS abaixo_minimo
FROM b
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_alimento   FROM workspace.bronze.dim_alimento)   a
       ON a._data_referencia = b._data_referencia AND a.sk_alimento = b.sk_alimento
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_perfil     FROM workspace.bronze.dim_perfil)     p
       ON p._data_referencia = b._data_referencia AND p.sk_perfil = b.sk_perfil
LEFT JOIN (SELECT DISTINCT _data_referencia, sk_localidade FROM workspace.bronze.dim_localidade) l
       ON l._data_referencia = b._data_referencia AND l.sk_localidade = b.sk_localidade
WHERE b.rn = 1;

-- ===================================================================== GABARITO
-- KPIs calculados pelo próprio banco (vw_kpi_cards), só para conferir a Gold.
CREATE OR REFRESH MATERIALIZED VIEW workspace.silver.kpi_cards_gabarito
COMMENT 'Gabarito: KPIs da view bi.vw_kpi_cards do banco, por foto diária (não entra no cálculo)'
AS
SELECT _data_referencia                    AS data_referencia,
       codigo, kpi,
       CAST(valor  AS DECIMAL(12,2))       AS valor,
       unidade, meta,
       CAST(desvio AS DECIMAL(12,2))       AS desvio,
       situacao
FROM (
  SELECT *, ROW_NUMBER() OVER (PARTITION BY _data_referencia, codigo ORDER BY _ingerido_em DESC) AS rn
  FROM workspace.bronze.vw_kpi_cards
) WHERE rn = 1;
