# NexUs-DB

Banco de dados do NexUs — gestão de alimentos em geladeira, freezer e despensa. Este repositório contém o modelo relacional (PostgreSQL), a camada de dados do MongoDB, a carga de dados (dataload), o catálogo de metadados e scripts auxiliares.

PostgreSQL MongoDB Python

## O que tem aqui

O repositório tem quatro frentes:

- **Schema SQL** — DDL, enums, funções e triggers do PostgreSQL, versionado com Flyway sob `migrations/`.
- **Dataload** — popula dados fictícios no PostgreSQL e no MongoDB (`script/dataload`), assumindo o schema já aplicado.
- **Catálogo de metadados** — o que cada tabela, coluna e collection significa, com tipo, chaves e classificação LGPD (`script/05_catalogo/` e `doc/catalogo/`).
- **Auxiliares** — views de BI, monitoramento de DAU e placeholders para trabalhos futuros.

```
NexUs-DB/
├── migrations/                # migrations Flyway (schema versionado)
├── script/
│   ├── 03_bi_views/          # data mart (star schema) para BI
│   ├── 04_monitoramento/     # monitoramento (DAU — Daily Active Users)
│   ├── 05_catalogo/          # SQL do catálogo de metadados (schema catalogo)
│   └── dataload/             # carga de dados (Postgres + Mongo)
├── doc/
│   └── catalogo/             # catálogo de metadados (PostgreSQL, data mart, MongoDB)
├── rpa/                      # automação (a preencher)
├── requirements.txt
└── .env                      # credenciais (não versionado)
```

## Catálogo de metadados

O catálogo existe como tabela no banco (schema `catalogo`) e como documento para leitura:

| Arquivo | Conteúdo |
|---------|----------|
| [catalogo_metadados.md](doc/catalogo/catalogo_metadados.md) | Catálogo completo: PostgreSQL (tabelas, enums, regras, diagrama ER), data mart (`bi`/`bi_hist`) e MongoDB |
| [01_estrutura.sql](script/05_catalogo/01_estrutura.sql) | Recria o schema `catalogo`: tabelas `catalogo.objeto` e `catalogo.coluna` e a view `catalogo.vw_dicionario_dados` |
| [02_metadados_postgres.sql](script/05_catalogo/02_metadados_postgres.sql) | Carrega os metadados das tabelas e views do PostgreSQL |
| [03_metadados_mongodb.sql](script/05_catalogo/03_metadados_mongodb.sql) | Carrega os metadados das collections do MongoDB |

Para cada coluna o catálogo traz tipo, nulidade, padrão, chave (PK/FK/UK), descrição e classificação LGPD:

| Classificação | Significado | Exemplos |
|---------------|-------------|----------|
| `INTERNO` | Dado de negócio, sem dado pessoal | `food.gtin`, `payment.amount` |
| `PESSOAL` | Identifica ou localiza uma pessoa | `profile.email`, `address.street` |
| `SENSIVEL` | Dado pessoal sensível (saúde, religião) | `profile.dietary_restriction` |
| `SIGILOSO` | Credencial | `auth_method.credential` |

Ao alterar o schema ou uma collection, atualize o catálogo no mesmo PR.

O catálogo não é versionado com Flyway: os scripts podem rodar de novo quando quiser, e o
histórico das mudanças fica no git. Para carregar tudo, rode na ordem:

```bash
psql -h <host> -U <usuario> -d <banco> -f script/05_catalogo/01_estrutura.sql
psql -h <host> -U <usuario> -d <banco> -f script/05_catalogo/02_metadados_postgres.sql
psql -h <host> -U <usuario> -d <banco> -f script/05_catalogo/03_metadados_mongodb.sql
```

Para mudar só o MongoDB, edite o `03_metadados_mongodb.sql` e rode só ele: ele apaga e
recarrega apenas os metadados do MongoDB (o mesmo vale para o `02` e o PostgreSQL). O `01`
recria o schema do zero, então depois dele rode o `02` e o `03`.

```sql
SELECT * FROM catalogo.vw_dicionario_dados WHERE objeto_nome = 'profile' ORDER BY posicao;
```

## Schema PostgreSQL

O schema é versionado com [Flyway](https://flywaydb.org/) em `migrations/` — mesmo
contrato de banco usado pelo `auth-api` e pelo `NexUs-Core`. Veja
[migrations/README.md](migrations/README.md) para como aplicar (inclui o passo de
baseline necessário nos ambientes onde essas migrations já foram executadas
manualmente).

### Enums

| Enum | Valores |
|------|---------|
| `profile_type_enum` | `HOUSEHOLD`, `ADMIN`, `COMPANY`, `STORE` |
| `profile_status_enum` | `ACTIVE`, `INACTIVE`, `BLOCKED` |
| `unit_of_measure_enum` | `g`, `kg`, `ml`, `l`, `unit` |
| `payment_status_enum` | `PENDING`, `PAID`, `OVERDUE`, `CANCELLED` |
| `auth_provider_enum` | `GOOGLE`, `PASSWORD` (removido `MICROSOFT` na V2) |

### Tabelas

| Tabela | Finalidade |
|--------|-----------|
| `category` | Categorias de alimentos |
| `food` | Alimentos (produtos) do catálogo |
| `address` | Endereços |
| `profile` | Perfis (household, company, store, admin); inclui `dietary_restriction` (restrições alimentares do household) |
| `profile_phone` | Telefones do perfil |
| `auth_method` | Métodos de autenticação (Google/senha) |
| `plan` | Planos de assinatura |
| `company` | Empresas (vinculadas a um profile COMPANY) |
| `store` | Lojas (vinculadas a uma company) |
| `payment` | Pagamentos de planos |
| `pantry_item` | Itens no estoque doméstico |
| `pantry_product_setting` | Configuração de quantidade mínima por alimento |
| `daily_active_users` | Usuários (profiles) ativos por dia — criada por `script/04_monitoramento/script_dau.sql`, fora do Flyway |

### Regras de negócio

As regras vivem em funções + triggers, não na camada de aplicação:

- **`validate_profile_reference_type(tipo)`** — garante que `profile_id` de `pantry_item`, `pantry_product_setting`, `company` e `store` aponte para um profile do tipo esperado (`HOUSEHOLD`, `COMPANY`, `STORE`). Aplica via triggers de `BEFORE INSERT/UPDATE`.
- **`prevent_profile_type_change()`** — impede que o `type` de um profile seja alterado depois de criado.
- **`register_daily_activity(user_id)`** — registra o acesso/login do usuário no DAU do dia com `INSERT ... ON CONFLICT DO NOTHING` (uma linha por usuário por dia). Uso: `SELECT register_daily_activity(<profile_id>)`. Detalhes em [script/04_monitoramento/README.md](script/04_monitoramento/README.md).

Nota sobre IDs: as tabelas usam `SERIAL PRIMARY KEY` (auto-incremento nativo do Postgres).

## Dataload

O dataload em `script/dataload/` popula os dois bancos com dados fictícios
determinísticos (seed fixo). Ele **não aplica mais o schema** — isso agora é
responsabilidade do Flyway (`migrations/`), rodado antes do dataload.

Dependências: `psycopg2-binary`, `pymongo`, `faker`, `faker_food`, `python-dotenv` (ver `requirements.txt`).

```bash
pip install -r requirements.txt
```

Comandos (rodar a partir da raiz `NexUs-DB/`, com o schema já aplicado via Flyway):

```bash
python -m script.dataload.src.main seed-sql    # popula o PostgreSQL
python -m script.dataload.src.main seed-mongo  # popula o MongoDB
python -m script.dataload.src.main all         # seed-sql + seed-mongo
python -m script.dataload.src.main register-dau --profile-id 1  # registra acesso no DAU
```

Configuração: o arquivo `.env` (na raiz) é carregado pelo dataload:

```env
PG_HOST=...
PG_PORT=...
PG_DATABASE=...
PG_USER=...
PG_PASSWORD=...

MONGO_URI=...
MONGO_DB=...
```

Detalhes de implementação do dataload (factories, seeders, collections do Mongo) estão em [script/dataload/README.md](script/dataload/README.md).

## Configuração do ambiente

- Crie um `.env` na raiz com as credenciais de PostgreSQL e MongoDB (o `.env` é o único arquivo ignorado no `.gitignore`).
- Aplique o schema com Flyway (`migrations/`) antes de rodar o dataload.
- Para a métrica de DAU, rode `script/04_monitoramento/script_dau.sql` no banco (manual, depois das migrations).

## Em andamento / placeholders

- `rpa/` — vazio, aguardando trabalho.
- `profile.dietary_restriction` — documentado no catálogo, ainda sem migration (próxima: V8).
