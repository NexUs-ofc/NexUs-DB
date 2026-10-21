# Engenharia de dados — requisitos, validação e operação

Auditoria dos requisitos do trabalho, o que foi implementado e como cada item foi testado.
Bancos do projeto:

- **Legado:** PostgreSQL com tabelas `tb_*` (origem). Só é lido pelo RPA. O DDL real não está neste repositório.
- **Novo (normalizado):** PostgreSQL versionado pelas `migrations/` (destino), mais MongoDB para receitas, eventos e telemetria.

## 1. Matriz de conformidade

| # | Requisito | Antes | Agora | O que foi feito / evidência | Arquivos |
|---|---|---|---|---|---|
| 1 | Massa ≥ 500 registros | Concluído (sem validação registrada) | **Concluído** | Perfil BI gera 520 por tabela; `bi.vw_volume_tabelas` confirma ≥ 500 em 9 tabelas (category/plan são domínio fixo; company/store dividem os profiles). Reexecução não duplica (520 perfis BI após 2 cargas). | `script/dataload/src/bi.py` |
| 2a | Integração RPA legado → novo | Concluído | **Concluído (sem alteração)** | RPA já funcional, com o legado configurado no `.env`. Não foi modificado. Validado à parte com um legado de teste no ambiente isolado (não versionado): carga, reexecução sem duplicar (0 novos), correção de registro rejeitado, falha com `FALHA` em `rpa.execucao` e retomada. | `rpa/` |
| 2b | Data Mart (Star Schema) | Concluído | **Concluído** | 5 dimensões, 5 fatos, KPIs D1–D9 (sem alteração). | `script/03_bi_views/datamart_estrela.sql` |
| 2c | CTEs | Concluído | **Concluído** | `kpi_d6`, `kpi_d9`, `vw_kpi_cards` e a nova `kpi_d1_evolucao_mensal`. | idem |
| 2d | Window Functions (Running Total, Ranking) | Parcial (só ranking) | **Concluído** | Nova `bi.kpi_d1_evolucao_mensal`: running total (`SUM OVER`), `LAG`, média móvel e `RANK`. Conferido: soma dos meses = último acumulado. | idem |
| 3a | 2 Functions + 2 Procedures | Concluído | **Concluído** | `fn_get_expiring_products`, `fn_get_items_below_minimum`, `sp_generate_monthly_payments`, `sp_update_overdue_payments` executadas; erro de parâmetro e idempotência da cobrança (57 → 0 na 2ª chamada) verificados. | `migrations/V8__...sql` |
| 3b | Triggers de auditoria (NEW, OLD, TG_OP, CURRENT_USER) em 2 tabelas | Pendente | **Concluído** | `profile` e `payment`. INSERT/UPDATE/DELETE testados com usuário não dono; `sp_update_overdue_payments` gerou 57 logs em profile e 5 em payment. | `migrations/V9__audit_triggers.sql` |
| 3c | EXPLAIN ANALYZE + índices | Parcial (índices da V8 sem medição) | **Concluído** | Os 5 índices da V8 medidos com e sem índice, com 400 mil itens em banco de teste e log completo (seção 4). Todos são usados. Ex.: despensa de uma casa 2.976 → 4 blocos lidos. Nenhum índice novo. | `script/06_otimizacao/explain_analyze.sql`, `doc/evidencias/explain_analyze.log` |
| 4a | Catálogo de dados (tabelas, colunas, regras, níveis de acesso) | Parcial (desatualizado, sem nível de acesso) | **Concluído** | Corrigido `dietary_restrictions` (V8), adicionados horários de loja, auditoria e a nova view; criados `regra_negocio` e `catalogo.nivel_acesso`. Comparação automática catálogo × banco: **0 diferenças** de nome, tipo e nulidade. | `script/05_catalogo/01_estrutura.sql`, `02_metadados_postgres.sql` |
| 4b | Backup e recuperação documentados | Pendente | **Concluído** | Seção 5. Backup, restore completo (contagens idênticas) e recuperação de linhas apagadas testados, com log completo. | este documento, `doc/evidencias/backup_restore.log` |
| 5 | DAU automatizado no Postgres | Pendente (arquivo vazio, só no catálogo) | **Concluído no banco / falta ligar no auth-api** | Tabela, função e view como o catálogo já descrevia + trigger em `pantry_item`. Deduplicação e fuso testados. | `script/04_monitoramento/script_dau.sql` |
| 6 | CTE recursiva ou herança | Pendente | **Concluído** | Herança: `auditoria.log_alteracao` (pai) → `log_profile`, `log_payment` (filhas). | `migrations/V9__audit_triggers.sql` |

## 2. Ordem de execução

```text
1. migrations/ (Flyway)            V1 … V9
2. script/dataload                  seed-sql  e  all --perfil bi
3. script/04_monitoramento/script_dau.sql
4. script/03_bi_views/datamart_estrela.sql
5. script/05_catalogo/01, 02, 03
6. rpa (python -m rpa.src.main)     quando houver legado
```

Os passos 3 a 5 podem ser repetidos (idempotentes). O 3 vem antes da carga do RPA para o
DAU já existir; se rodar depois, só as atividades seguintes são registradas.

## 3. Auditoria, DAU e herança

**Auditoria (V9).** Um trigger `AFTER INSERT OR UPDATE OR DELETE` em `profile` e `payment`
chama `auditoria.fn_registrar_alteracao()`, que grava `OLD` e `NEW` em JSONB, `TG_OP` e
`CURRENT_USER` na tabela filha `auditoria.log_<tabela>`.

```sql
-- todos os logs (tabela pai) e de qual filha cada um veio
SELECT tableoid::regclass AS origem, operacao, registro_id, usuario, alterado_em
FROM auditoria.log_alteracao ORDER BY id DESC LIMIT 20;

-- o que mudou no status de um perfil
SELECT operacao, dados_antigos->>'status' AS antes, dados_novos->>'status' AS depois, usuario, alterado_em
FROM auditoria.log_profile WHERE registro_id = 42 ORDER BY alterado_em;
```

Por que herança: a consulta na pai junta todas as tabelas auditadas, e cada filha pode ter
índices e retenção próprios. Para auditar outra tabela basta criar `auditoria.log_<tabela>
() INHERITS (auditoria.log_alteracao)` e o trigger. Cuidados: PK e índices não são herdados
(cada filha declara os seus) e os logs contêm dados pessoais — o catálogo marca
`dados_antigos`/`dados_novos` como `SENSIVEL`. O usuário da aplicação precisa de `INSERT`
nas tabelas e `USAGE` na sequence do schema `auditoria`.

**DAU.** Usuário = `profile.id`; dia = data em `America/Sao_Paulo`. A PK
`(activity_date, user_id)` impede contar o mesmo usuário duas vezes no dia; repetir o
registro só mantém o horário mais cedo (`first_seen_at`). Formas de registro:

- `SELECT register_daily_activity(<profile_id>);` — chamada pelo **auth-api a cada login**.
- Trigger `trg_dau_pantry_item` — o household incluiu ou alterou um item da despensa.
- Opcional: uma carga em lote pode rodar `SET nexus.carga_em_lote = 'on'` para não contar. O RPA não
  usa essa opção, então itens novos vindos do legado contam o household como ativo no dia da carga.

```sql
SELECT * FROM vw_dau ORDER BY activity_date DESC LIMIT 30;
```

Testado: 4 registros do mesmo usuário no mesmo dia → 1 linha; 23:30 de São Paulo (02:30
UTC do dia seguinte) conta no dia correto; com `nexus.carga_em_lote = 'on'` nenhum registro novo.

## 4. Otimização (EXPLAIN ANALYZE)

Os índices avaliados são os que **já existiam na `main`** (criados na V8). Nenhum índice novo
foi adicionado: o teste mostra, com `EXPLAIN ANALYZE`, o ganho de cada um nas consultas do app.

**Evidência completa:** [`doc/evidencias/explain_analyze.log`](evidencias/explain_analyze.log), a
saída integral do `psql`, com cada comando e o plano devolvido pelo Postgres. O log foi gerado
por [`script/06_otimizacao/explain_analyze.sql`](../script/06_otimizacao/explain_analyze.sql).

**Como o teste foi feito, sem tocar na produção:**

1. **Banco de teste.** O banco usado é `nexus_teste`, criado ao **restaurar o backup** (seção 5).
   O script tem uma trava: se o nome do banco não contém `teste`, ele para sem executar nada.
2. **Volume.** Com o volume normal (670 itens), qualquer consulta é instantânea. O script insere,
   **dentro de uma transação**, 20 mil casas, 2 mil empresas com 24 mensalidades cada
   (48 mil pagamentos), 100 mil alimentos e 400 mil itens de despensa.
3. **Medição sem índices.** Remove os índices da V8 temporariamente (com um `SAVEPOINT`) e roda
   `EXPLAIN (ANALYZE, BUFFERS)` nas 5 consultas.
4. **Medição com índices.** Volta os índices (`ROLLBACK TO SAVEPOINT`) e roda as mesmas 5 consultas.
5. **Limpeza.** Termina com `ROLLBACK`. No fim do log, `pantry_item` volta a 670 linhas e os 5
   índices continuam presentes.

| Consulta do app | Índice (V8) | Sem índice | Com índice | Blocos lidos |
|---|---|---|---|---|
| Q1 Vencimentos dos próximos 7 dias (`fn_get_expiring_products`) | `idx_pantry_expiry_id` | Seq Scan, 31,96 ms | Bitmap Index Scan, **4,46 ms** | 2.976 → **141** |
| Q2 Despensa de uma casa por validade (tela principal) | `idx_pantry_profile_expiry_id` | Seq Scan + Sort, 24,01 ms | Index Scan já ordenado, **0,021 ms** | 2.976 → **4** |
| Q3 Mensalidades pendentes vencidas (`sp_update_overdue_payments`) | `idx_payment_pending_due` (parcial) | Seq Scan, 3,92 ms | Bitmap Index Scan, **0,52 ms** | 553 → **272** |
| Q4 Busca de alimento por trecho do nome | `idx_food_name_lower_trgm` (GIN trigram) | Seq Scan, 40,42 ms | Bitmap Index Scan, **5,87 ms** | 1.225 → **480** |
| Q5 Login por e-mail sem diferenciar maiúsculas | `idx_profile_email_lower` | Seq Scan, 7,22 ms | Index Scan, **0,018 ms** | 325 → **3** |

Como ler os números:

- **Seq Scan** quer dizer que o Postgres leu a tabela inteira. **Index Scan** ou **Bitmap Index Scan**
  quer dizer que ele foi direto às linhas certas pelo índice.
- **Blocos lidos** (`Buffers: shared hit/read`) é quanto dado foi lido. É a medida mais estável.
- **Tempo** varia um pouco a cada execução, porque depende da máquina e do cache.

**Conclusões:**

- **Todos os 5 índices são usados** e reduzem o tempo de 4 a mais de mil vezes.
- **Q2 e Q5 são os maiores ganhos.** Buscam poucas linhas (uma casa, um e-mail) numa tabela
  grande, que é o caso ideal para um índice. A Q2 ainda dispensa o `Sort`, porque o índice já
  guarda os itens na ordem da tela.
- **Q3 usa um índice parcial** (`WHERE payment_status = 'PENDING'`): ele só guarda as pendências,
  por isso é pequeno.
- **Q4 depende do tamanho do catálogo.** Com 5 mil alimentos, numa versão anterior deste teste,
  o Postgres preferiu ler a tabela inteira, que era menor que o índice, mesmo com o índice
  disponível. Com 100 mil, o índice trigram passou a ser usado. Ou seja, o índice é para quando
  o catálogo crescer.
- **Nenhum índice novo foi necessário.** Cada índice deixa as escritas mais lentas, então só
  devem existir os que a medição justifica.

Para repetir (somente em banco de teste):

```bash
psql -d nexus_teste -e -f script/06_otimizacao/explain_analyze.sql > doc/evidencias/explain_analyze.log 2>&1
```

## 5. Backup e recuperação

Credenciais nunca vão na linha de comando: use as variáveis `PGHOST`, `PGPORT`, `PGUSER`,
`PGDATABASE` e o arquivo `~/.pgpass` (Windows: `%APPDATA%\postgresql\pgpass.conf`).

**Política sugerida:** backup lógico diário (formato custom, comprimido), retenção de 7
diários + 4 semanais, cópia fora do servidor do banco. RPO de até 24 h. Antes de toda
migration manual, um backup avulso. MongoDB tem backup próprio (`mongodump`).

```bash
# backup completo (schemas public, auditoria, catalogo, bi, bi_hist, rpa)
pg_dump -Fc -Z 6 -f nexus_$(date +%F).dump

# conferir o conteúdo do arquivo
pg_restore -l nexus_2026-10-17.dump | head

# restaurar em um banco NOVO (nunca por cima do banco em uso)
createdb nexus_restaurado
pg_restore -d nexus_restaurado --no-owner --exit-on-error nexus_2026-10-17.dump
```

**Recuperar linhas apagadas por engano** (sem derrubar o banco): restaure o backup em um
banco separado e copie só o que falta.

```bash
createdb nexus_recuperacao
pg_restore -d nexus_recuperacao --no-owner nexus_2026-10-17.dump
psql -d nexus_recuperacao -c "\copy (SELECT * FROM payment WHERE company_id = 7) TO 'pagamentos.csv' CSV HEADER"
psql -d <banco_em_uso>     -c "\copy payment FROM 'pagamentos.csv' CSV HEADER"
dropdb nexus_recuperacao
```

`auditoria.log_*` ajuda a descobrir o que foi apagado, quando e por quem
(`operacao = 'DELETE'`, com a linha inteira em `dados_antigos`).

**Falha total do servidor:** crie um servidor PostgreSQL 16 com PostGIS e pg_trgm, restaure o
último backup como acima e confira com
`SELECT * FROM bi.vw_volume_tabelas;` e (com Flyway) `SELECT max(version) FROM flyway_schema_history;`.
Dados gravados depois do backup são perdidos (RPO); o RPA pode ser reexecutado para recuperar
o que veio do legado.

**Evidência completa:** [`doc/evidencias/backup_restore.log`](evidencias/backup_restore.log), com cada
comando executado e a saída real. Resumo:

| Etapa | Resultado |
|---|---|
| Backup (`pg_dump -Fc`) | 291 KB em 0,3 s, 21 tabelas com dados, schemas auditoria, bi, bi_hist e catalogo incluídos |
| Restauração em banco novo (`nexus_teste`) | 0,7 s, código de saída 0 |
| Conferência origem × restaurado | profile 643, payment 598, pantry_item 670, food 560, auditoria 1241, catálogo 327 nos dois bancos |
| Objetos | 4 triggers recriados e views do BI funcionando |
| Acidente simulado | `DELETE` de 3 pagamentos (598 → 595); a auditoria mostra quais eram e quem apagou |
| Recuperação | 3 linhas copiadas de uma restauração separada (595 → 598, igual ao backup) |

O `nexus_teste` restaurado aqui é o banco usado depois no teste de EXPLAIN ANALYZE (seção 4).

## 6. Como foi validado

Ambiente isolado: PostgreSQL 16.15 + PostGIS 3.4.2, a mesma versão do CI
(`postgis/postgis:16-3.5`). Nada foi executado em bancos compartilhados. Do zero, na ordem da
seção 2: todas as migrations aplicaram sem erro (a V9 também foi reaplicada sem erro),
dataload padrão + BI, DAU, data mart e catálogo. As migrations foram aplicadas com `psql`
(uma transação por arquivo), não com o Flyway CLI; o CI aplicará com Flyway.

Não testado: o RPA contra o legado real (não executei em bancos compartilhados), o RPA pelo GitHub
Actions e o MongoDB (`seed-mongo`).
