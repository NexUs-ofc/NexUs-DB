# Relatório de justificativa — NexUs-DB

Projeto Interdisciplinar 2026 · Entrega Final — 2º ano · 02/11/2026

Este relatório mostra, para cada requisito, o que foi desenvolvido, como foi desenvolvido e onde está
no repositório. Os links apontam para a branch `main` e abrem o arquivo já na linha da demanda.
O repositório é público, então os professores acessam sem liberação adicional.

Repositório: https://github.com/NexUs-ofc/NexUs-DB

---

## 1. Modelagem de Dados

### 1.1 Novo Banco Normalizado

**Requisito:** criar um novo banco de dados relacional (PostgreSQL) normalizado até a 3ª Forma Normal (3FN) e, caso seja necessário, até a 5ª Forma Normal.

**O que foi desenvolvido:** schema relacional com 13 tabelas de negócio no schema `public` e 5 tipos ENUM, versionado com Flyway em 13 migrations (V1 a V13) e um callback que cria o histórico de estoque em banco novo. Um banco vazio sobe com um único `flyway migrate`.

**Como foi desenvolvido:**

- **1FN:** atributos multivalorados viraram tabelas próprias: telefones em `profile_phone` e métodos de login em `auth_method`.
- **2FN:** as tabelas usam chave substituta (`SERIAL`). Nas PKs compostas (`profile_phone`, `daily_active_users`) nenhum atributo depende só de parte da chave.
- **3FN:** categoria, endereço e plano ficam em tabelas próprias, referenciadas por FK, sem dependências transitivas entre atributos não chave.
- **Desnormalizações conscientes:**
  - `payment.plan_id` e `payment.amount` guardam o plano e o preço vigentes na competência, para que uma mudança de plano não altere cobranças passadas.
  - Em `address`, cidade e UF são gravadas junto com o CEP porque o app recebe o endereço digitado e não consulta uma base oficial de CEPs.
  - `profile.dietary_restrictions` é uma lista de códigos (`TEXT[]`) cujo catálogo vive no frontend e não é consultada pelo banco.
- **Domínios:** ENUM para tipo e status de perfil, unidade de medida, status de pagamento e provedor de login. CHECK para CEP, CNPJ, UF, telefone (E.164), quantidades e horário de loja.
- **4FN/5FN:** as relações N:N (perfil × alimento) carregam atributos próprios (quantidade, validade, mínimo) e nenhuma tabela combina fatos multivalorados independentes, então não há dependência multivalorada nem de junção a decompor.

**Links:**

- [Pasta migrations/](https://github.com/NexUs-ofc/NexUs-DB/tree/main/migrations)
- [V1__initial_schema.sql — ENUMs e tabelas](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V1__initial_schema.sql#L1-L119)
- [Callback que cria o histórico em banco novo](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/beforeMigrate__bi_hist_registro_estoque.sql)
- Visualização da modelagem no dbdiagram.io: {link do dbdiagram}

### 1.2 Relacionamentos

**Requisito:** definir claramente todas as PKs, FKs e cardinalidades (1:1, 1:N, N:N).

**O que foi desenvolvido:** PK em todas as tabelas de negócio, FKs com ação referencial definida pela regra de negócio e diagrama entidade-relacionamento no catálogo de dados.

**Como foi desenvolvido:**

- **1:1** (1:0..1): `profile` ↔ `company` e `profile` ↔ `store`, pela FK `profile_id` com `UNIQUE`. Um trigger garante que o perfil seja do tipo certo (COMPANY ou STORE).
- **1:N:**
  - `category` → `food`, `plan` → `company`, `company` → `store`, `company` → `payment`;
  - `profile` → `profile_phone` e `auth_method`;
  - `address` → `profile` (obrigatório para HOUSEHOLD e STORE).
- **N:N:** `profile` × `food`, por duas tabelas associativas:
  - `pantry_item`: lotes de estoque, vários por par;
  - `pantry_product_setting`: quantidade mínima, `UNIQUE (profile_id, food_id)`.
- **Ações referenciais:**
  - `CASCADE` para o que pertence ao perfil (telefones, logins, despensa, histórico de estoque e `billing_block`);
  - `RESTRICT` para domínios (categoria, endereço).

**Links:**

- [V1__initial_schema.sql — tabelas, PKs e FKs](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V1__initial_schema.sql#L7-L119)
- [Diagrama entidade-relacionamento](https://github.com/NexUs-ofc/NexUs-DB/blob/main/doc/catalogo/catalogo_metadados.md#L81-L211)
- [V13 — billing_block e histórico em cascata](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V13__fix_history_cascade_audit_protection_and_billing_block.sql#L9-L31)
- Visualização da modelagem no dbdiagram.io: {link do dbdiagram}

### 1.3 Massa de Dados

**Requisito:** carga inicial de pelo menos 500 registros verossímeis para testes de volume.

**O que foi desenvolvido:** dataload em Python que popula PostgreSQL e MongoDB. O perfil BI simula 12 meses de uso e gera, por execução:

| Tabela | Registros |
| --- | --- |
| `profile` e `address` | 520 (380 casas, 55 empresas, 85 lojas) |
| `food` | 520 |
| `payment` | 566 |
| `pantry_item` | 12.579 lotes (incluindo os encerrados com saldo zero) |
| `pantry_product_setting` | 2.248 |
| `bi_hist.registro_estoque` | 9.590 movimentos |

**Como foi desenvolvido:**

- Faker (pt_BR) e faker_food com seed fixo; a data de referência pode ser fixada com `BI_DATA_REF`.
- Produtos com EAN-13 com dígito verificador, CEP de 8 dígitos, telefones em E.164 e 60 cidades das 27 UFs.
- Idempotente: cada execução remove a carga anterior (e-mails `@bi.nexus.local`) e insere de novo, sem duplicar.
- A view `bi.vw_volume_tabelas` mostra a contagem por tabela. `category` (17) e `plan` (3) são domínios fixos. `company` e `store` ficam abaixo de 500 porque cada uma também é um perfil.

**Links:**

- [Pasta script/dataload/](https://github.com/NexUs-ofc/NexUs-DB/tree/main/script/dataload)
- [bi.py — volumes da massa](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/dataload/src/bi.py#L35-L41)
- [bi.py — carga](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/dataload/src/bi.py#L529)
- [bi.vw_volume_tabelas](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L302-L322)

---

## 2. Engenharia de Dados e ETL

### 2.1 Integração RPA

**Requisito:** orquestrar a movimentação de dados entre o banco legado e o novo banco normalizado via RPA, garantindo a integridade e tratando falhas na carga.

**O que foi desenvolvido:** robô ETL em Python que migra `tb_categoria`, `tb_alimento`, `tb_usuario` (com o endereço da 1ª casa), `tb_casa`, `tb_telefone` e `tb_item_dispensa` para o banco novo. Roda todo dia às 03:00 (Brasília) pelo GitHub Actions e pode ser disparado manualmente.

**Como foi desenvolvido:**

- **Leitura consistente:** o legado é lido em uma única transação somente leitura `REPEATABLE READ`, então todas as etapas veem o mesmo retrato.
- **Integridade:** cada etapa é uma transação no banco novo, gravando o registro e o mapeamento juntos, na ordem das FKs.
- **Idempotência:** `rpa.mapeamento (entidade, id_legado, id_novo)` faz a carga incremental; o que já foi migrado é pulado.
- **Falha de dado:** um registro inválido (CEP, UF fora das 27 siglas, e-mail, telefone, quantidade, duplicidade) é desfeito por `SAVEPOINT`, registrado no log como rejeitado e reavaliado na próxima execução. O log não traz e-mail, CEP nem telefone.
- **Falha de infraestrutura:** só a etapa em andamento é desfeita. `rpa.execucao` registra `FALHA` com etapa e mensagem, mesmo que a conexão com o banco novo tenha caído, e a próxima execução retoma sem duplicar.
- **Conversões:**
  - categorias reaproveitadas sem diferenciar maiúsculas;
  - estado por extenso convertido em sigla;
  - telefone convertido para E.164.
- **DAU:** a carga não conta os usuários como ativos (`nexus.carga_em_lote = 'on'`).
- **Escopo:** a carga é só de inclusão. Alterações e exclusões feitas no legado depois da migração não são propagadas.

**Links:**

- [Pasta rpa/](https://github.com/NexUs-ofc/NexUs-DB/tree/main/rpa)
- [main.py — orquestração](https://github.com/NexUs-ofc/NexUs-DB/blob/main/rpa/src/main.py#L99-L144)
- [main.py — registro de falha](https://github.com/NexUs-ofc/NexUs-DB/blob/main/rpa/src/main.py#L76-L96)
- [etapas.py — SAVEPOINT por registro](https://github.com/NexUs-ofc/NexUs-DB/blob/main/rpa/src/etapas.py#L64-L75)
- [rpa.yml — agendamento](https://github.com/NexUs-ofc/NexUs-DB/blob/main/.github/workflows/rpa.yml#L1-L10)

### 2.2 Camada de BI (Data Mart)

**Requisito:** criar Views Analíticas desenhadas para ferramentas de BI, utilizando Modelagem Dimensional (Star Schema ou Snowflake).

**O que foi desenvolvido:** schema `bi` em Star Schema, implementado com views sobre o banco do app.

| Tipo | View | Grão |
| --- | --- | --- |
| Dimensão | `dim_tempo` | 1 dia (cobre todas as datas usadas pelas fatos) |
| Dimensão | `dim_alimento` (com a categoria) | 1 alimento |
| Dimensão | `dim_localidade` (cidade, UF, região) | 1 endereço |
| Dimensão | `dim_perfil` | 1 perfil |
| Dimensão | `dim_empresa` (com o plano) | 1 empresa |
| Fato | `fato_estoque` | 1 lote com saldo hoje |
| Fato | `fato_movimento` | 1 movimento de consumo ou descarte, com a quantidade |
| Fato | `fato_estoque_minimo` | casa × alimento monitorado |
| Fato | `fato_pagamento` | 1 cobrança mensal |
| Fato | `fato_cadastro` | 1 perfil |

Views de indicadores, consolidadas em `vw_kpi_cards` com valor, meta, desvio e situação:

- D1 taxa de desperdício e D9 desperdício por categoria (por unidades descartadas);
- D3 % de itens vencidos, D4 % a vencer em 7 dias, D8 % sem validade;
- D5 ranking de vencimento por UF;
- D6 estoque abaixo do mínimo;
- D7 vida útil por categoria;
- inadimplência, pagamento no prazo e base ativa.

**Como foi desenvolvido:**

- Cada fato tem o grão declarado e aponta só para dimensões; a chave `-1` representa "não informado".
- As dimensões são desnormalizadas: categoria em `dim_alimento`, plano em `dim_empresa`.
- Nenhuma view expõe nome, e-mail, telefone ou rua.
- O mesmo modelo alimenta o pipeline Bronze → Silver → Gold no Databricks.

**Links:**

- [datamart_estrela.sql — dimensões e fatos](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L30-L146)
- [datamart_estrela.sql — cards de indicadores](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L258-L296)
- [README do Data Mart](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/README.md)
- [Pasta business-intelligence/databricks/](https://github.com/NexUs-ofc/NexUs-DB/tree/main/business-intelligence/databricks)

### 2.3 Transformação (ETL no SQL): CTEs

**Requisito:** utilizar CTEs para organizar a lógica de transformação de dados.

**O que foi desenvolvido:** views de indicadores escritas em etapas com `WITH`, uma CTE por passo:

| View | CTEs |
| --- | --- |
| `kpi_d1_evolucao_mensal` | `mensal` agrega os movimentos por mês; `meses` gera todos os meses do período; `indicadores` junta os dois e calcula a taxa de cada mês |
| `kpi_d6_estoque_minimo_uf` | `casa` reduz o grão de casa × alimento para uma linha por casa |
| `kpi_d9_desperdicio_categoria` | `uso` junta histórico e despensa para saber quais casas tiveram cada categoria |
| `vw_kpi_cards` | `k` reúne os indicadores em linhas homogêneas para calcular meta, desvio e situação de uma vez |

**Como foi desenvolvido:** cada CTE entrega um resultado intermediário que a etapa seguinte reutiliza. Na evolução mensal, por exemplo, primeiro se agrega por mês, depois se completam os meses sem movimento e só então entram os cálculos analíticos.

**Links:**

- [CTEs mensal, meses e indicadores](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L163-L196)
- [CTE casa (estoque mínimo)](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L222-L231)
- [CTE uso (desperdício por categoria)](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L244-L255)
- [CTE k (cards de indicadores)](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L258-L296)

### 2.4 Transformação (ETL no SQL): Window Functions

**Requisito:** implementar cálculos analíticos (ex.: Running Total, Ranking) nas views de BI.

**O que foi desenvolvido:**

- **Running Total:** `SUM(perda_rs) OVER (ORDER BY ano_mes ROWS UNBOUNDED PRECEDING)`, a perda acumulada.
- **Variação mês a mês:** `LAG(taxa_desperdicio_pct)`.
- **Média móvel de 3 meses:** `AVG(...) OVER (ORDER BY ano_mes ROWS 2 PRECEDING)`.
- **Rankings:**
  - `RANK() ... DESC NULLS LAST` dos meses por perda;
  - `DENSE_RANK()` das UFs por itens vencidos ou a vencer em 30 dias;
  - `DENSE_RANK()` das categorias por índice de desperdício.

**Como foi desenvolvido:**

- As funções rodam sobre o resultado agregado das CTEs.
- Como a CTE `meses` inclui os meses sem movimento, `LAG` e a média móvel comparam com o mês anterior do calendário.
- Meses sem perda estimada ficam sem posição no ranking.
- Validação: a soma da perda dos meses é igual ao último valor acumulado.

**Links:**

- [Running Total, LAG, média móvel e RANK](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L163-L196)
- [DENSE_RANK por UF (ranking de vencimento)](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L212-L219)
- [DENSE_RANK por categoria (desperdício)](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/03_bi_views/datamart_estrela.sql#L244-L255)

---

## 3. Objetos Lógicos e Otimização

### 3.1 SQL Avançado

**Requisito:** mínimo de 2 Functions e 2 Procedures para regras de negócio críticas.

**O que foi desenvolvido:**

| Objeto | Tipo | Regra de negócio |
| --- | --- | --- |
| `fn_get_expiring_products(inicio, fim)` | Function | Itens de perfis ativos que vencem na janela informada |
| `fn_get_items_below_minimum(profile_id)` | Function | Alimentos abaixo do mínimo, sem contar lotes vencidos e incluindo alimentos sem estoque |
| `sp_generate_monthly_payments(data, dia)` | Procedure | Gera uma cobrança por empresa e competência |
| `sp_update_overdue_payments(tolerancia)` | Procedure | Marca cobranças vencidas, bloqueia empresa e lojas inadimplentes e reativa quem quitou |

**Como foi desenvolvido:**

- Todas em PL/pgSQL, com validação de parâmetros: intervalo invertido, dia de vencimento fora de 1 a 28, tolerância negativa e perfil inválido levantam erro com `ERRCODE 22023`.
- A geração de cobrança é idempotente (`NOT EXISTS` + `ON CONFLICT` no índice único `(company_id, billing_period_start)`): criou 57 mensalidades na 1ª chamada e 0 na 2ª.
- O bloqueio por inadimplência fica registrado em `billing_block`, e o job só reativa os perfis que ele mesmo bloqueou. Um bloqueio manual não é desfeito.

**Links:**

- [V8 — Functions e Procedures](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V8__profile_restrictions_store_hours_billing_and_indexes.sql#L81-L269)
- [V13 — sp_update_overdue_payments com billing_block](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V13__fix_history_cascade_audit_protection_and_billing_block.sql#L135-L237)
- [V13 — validação em fn_get_items_below_minimum](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V13__fix_history_cascade_audit_protection_and_billing_block.sql#L239-L282)

### 3.2 Triggers de Auditoria

**Requisito:** logs completos (NEW, OLD, TG_OP, CURRENT_USER) em pelo menos 2 tabelas.

**O que foi desenvolvido:** triggers `trg_audit_profile` e `trg_audit_payment`, que chamam a função genérica `auditoria.fn_registrar_alteracao()`.

**Como foi desenvolvido:**

- Disparam em `AFTER INSERT OR UPDATE OR DELETE`, por linha.
- Gravam `OLD` e `NEW` em JSONB (`OLD` nulo no INSERT, `NEW` nulo no DELETE), `TG_OP`, `CURRENT_USER`, o id do registro e a data/hora (`clock_timestamp()`).
- A função escolhe a tabela de destino pelo nome (`log_profile`, `log_payment`), então auditar outra tabela é criar a filha e o trigger.
- **Proteção dos logs:**
  - um trigger recusa INSERT direto nas tabelas de log e grava sempre o usuário e o horário reais, então ninguém consegue forjar um log;
  - os serviços não têm UPDATE nem DELETE no schema `auditoria`.
- **Dado sensível:** `dietary_restrictions` (classificado como SENSIVEL no catálogo) vai para o log só como hash MD5.
- Testado com um usuário que não é dono das tabelas.

**Links:**

- [V10 — função e triggers de auditoria](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V10__audit_triggers.sql#L28-L59)
- [V13 — máscara de dado sensível e proteção dos logs](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V13__fix_history_cascade_audit_protection_and_billing_block.sql#L33-L133)

### 3.3 Otimização

**Requisito:** analisar consultas lentas com EXPLAIN ANALYZE e aplicar Índices (SQL) para otimização.

**O que foi desenvolvido:** índices da V8 criados para as consultas do app (entre eles um índice parcial e um GIN trigram) e medição com `EXPLAIN (ANALYZE, BUFFERS)` de 5 consultas, sem e com os índices.

**Como foi desenvolvido:**

- O teste roda num banco restaurado do backup, nunca na produção (o script para se o nome do banco não contém "teste").
- Dentro de uma transação, insere 400 mil lotes, 100 mil alimentos e 48 mil pagamentos.
- Mede com os índices removidos (SAVEPOINT), mede com os índices e termina em ROLLBACK.

| Consulta | Índice | Sem índice | Com índice | Blocos lidos |
| --- | --- | --- | --- | --- |
| Vencimentos em 7 dias | `idx_pantry_expiry_id` | 31,96 ms | 4,46 ms | 2.976 → 141 |
| Despensa de uma casa | `idx_pantry_profile_expiry_id` | 24,01 ms | 0,021 ms | 2.976 → 4 |
| Pendências vencidas | `idx_payment_pending_due` (parcial) | 3,92 ms | 0,52 ms | 553 → 272 |
| Busca por trecho do nome | `idx_food_name_lower_trgm` (GIN) | 40,42 ms | 5,87 ms | 1.225 → 480 |
| Login por e-mail | `idx_profile_email_lower` | 7,22 ms | 0,018 ms | 325 → 3 |

Os ganhos vão de cerca de 7 vezes a cerca de 1.100 vezes. Sem os índices, as cinco consultas leem a tabela inteira (Seq Scan).

**Links:**

- [explain_analyze.sql](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/06_otimizacao/explain_analyze.sql)
- [explain_analyze.log (evidência)](https://github.com/NexUs-ofc/NexUs-DB/blob/main/doc/evidencias/explain_analyze.log)
- [V8 — criação dos índices](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V8__profile_restrictions_store_hours_billing_and_indexes.sql#L18-L79)
- [Resultados comentados](https://github.com/NexUs-ofc/NexUs-DB/blob/main/doc/engenharia_de_dados.md#L82-L139)

---

## 4. Governança de Dados

### 4.1 Catálogo de Dados

**Requisito:** criar uma tabela técnica de metadados descrevendo cada tabela, suas colunas, regras de negócio e níveis de acesso.

**O que foi desenvolvido:** schema `catalogo` com:

- `catalogo.objeto`: tabela, view ou collection, com descrição e `regra_negocio`;
- `catalogo.coluna`: tipo, nulidade, padrão, chave, referência, descrição e classificação LGPD;
- `catalogo.nivel_acesso`: quem acessa cada classificação e como;
- a view `catalogo.vw_dicionario_dados`, que junta tudo em uma linha por coluna.

**Como foi desenvolvido:**

- Classificação LGPD por coluna (INTERNO, PESSOAL, SENSIVEL, SIGILOSO), ligada por FK a `nivel_acesso`.
- Cobre os schemas `public`, `bi`, `bi_hist` e `auditoria` e as collections do MongoDB.
- Comparação automática entre o catálogo e o `information_schema` (nome, tipo e nulidade de cada coluna): 0 diferenças.

**Links:**

- [Pasta script/05_catalogo/](https://github.com/NexUs-ofc/NexUs-DB/tree/main/script/05_catalogo)
- [01_estrutura.sql — tabelas do catálogo](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/05_catalogo/01_estrutura.sql#L13-L96)
- [catalogo_metadados.md](https://github.com/NexUs-ofc/NexUs-DB/blob/main/doc/catalogo/catalogo_metadados.md)

### 4.2 Segurança e Integridade

**Requisito:** definir procedimentos documentados para Backup e Recuperação de falhas.

**O que foi desenvolvido:** política e procedimentos documentados para três situações:

1. restauração completa;
2. recuperação de linhas apagadas por engano;
3. falha total do servidor.

**Como foi desenvolvido:**

- **Política:** `pg_dump -Fc` diário, retenção de 7 diários + 4 semanais, cópia fora do servidor e RPO de 24 h. O MongoDB usa `mongodump`.
- **Credenciais:** ficam em variáveis de ambiente e no `.pgpass`, nunca na linha de comando.
- **Restauração completa:** sempre em um banco novo. Testada com contagens iguais às do original (profile 643, payment 598, pantry_item 670).
- **Linhas apagadas:** a auditoria mostra o que foi apagado, quando e por quem, e as linhas são copiadas de uma restauração separada. Testado com 598 → 595 → 598 pagamentos.

**Links:**

- [engenharia_de_dados.md — Backup e recuperação](https://github.com/NexUs-ofc/NexUs-DB/blob/main/doc/engenharia_de_dados.md#L140-L194)
- [backup_restore.log (evidência)](https://github.com/NexUs-ofc/NexUs-DB/blob/main/doc/evidencias/backup_restore.log)

---

## 5. Monitoramento

**Requisito:** automatizar o registro de acessos DAU (Daily Active User) diretamente no banco Postgres.

**O que foi desenvolvido:** tabela `daily_active_users`, função `register_daily_activity()`, trigger `trg_dau_pantry_item` e view `vw_dau`.

**Como foi desenvolvido:**

- A PK `(activity_date, user_id)` impede contar o mesmo usuário duas vezes no dia; repetir o registro só mantém o primeiro horário.
- O dia é calculado no fuso `America/Sao_Paulo`: 23:30 de São Paulo conta no dia certo mesmo com o servidor em UTC.
- O trigger registra a atividade automaticamente quando o usuário inclui ou altera um item da despensa.
- A função `register_daily_activity()` é o ponto de registro do login, chamado pelo serviço de autenticação.
- Cargas em lote (dataload BI e RPA) não contam como acesso (`nexus.carga_em_lote = 'on'`).

**Links:**

- [script_dau.sql](https://github.com/NexUs-ofc/NexUs-DB/blob/main/script/04_monitoramento/script_dau.sql#L12-L62)

---

## 6. Estruturas Avançadas

**Requisito:** implementar, onde fizer sentido, CTE Recursiva ou Herança de Tabelas.

**O que foi desenvolvido:** Herança de Tabelas na auditoria. `auditoria.log_alteracao` é a tabela pai, e `log_profile` e `log_payment` são filhas criadas com `INHERITS`.

**Como foi desenvolvido:**

- **Por que faz sentido aqui:** todo log tem a mesma estrutura, mas cada tabela auditada tem volume e retenção diferentes.
- **Consulta unificada:** uma consulta na tabela pai junta os logs de todas as tabelas auditadas, e `tableoid::regclass` mostra de qual filha veio cada linha.
- **O que é herdado:** colunas, defaults e CHECKs. A PK não é herdada, então cada filha declara a sua.
- **Identificadores:** a sequence do `id` é compartilhada, então o id é único entre as filhas.

**Links:**

- [V10__audit_triggers.sql — tabela pai e filhas (INHERITS)](https://github.com/NexUs-ofc/NexUs-DB/blob/main/migrations/V10__audit_triggers.sql#L7-L26)
