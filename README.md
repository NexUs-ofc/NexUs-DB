# NexUs-DB

Banco de dados do NexUs — gestão de alimentos em geladeira, freezer e despensa. Este repositório contém o modelo relacional (PostgreSQL), a camada de dados do MongoDB, a carga de dados (dataload) e scripts auxiliares.

PostgreSQL MongoDB Python

## O que tem aqui

O repositório tem três frentes:

- **Schema SQL** — DDL, enums, funções e triggers do PostgreSQL, versionado com Flyway sob `migrations/`.
- **Dataload** — popula dados fictícios no PostgreSQL e no MongoDB (`script/dataload`), assumindo o schema já aplicado.
- **Auxiliares** — views de BI, scripts de monitoramento e placeholders para trabalhos futuros.

```
NexUs-DB/
├── migrations/                # migrations Flyway (schema versionado)
├── script/
│   ├── 03_bi_views/          # views de BI (a definir)
│   ├── 04_monitoramento/     # scripts de monitoramento
│   └── dataload/             # carga de dados (Postgres + Mongo)
├── doc/                      # documentação (a preencher)
├── rpa/                      # automação (a preencher)
├── requirements.txt
└── .env                      # credenciais (não versionado)
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
| `profile` | Perfis (household, company, store, admin) |
| `profile_phone` | Telefones do perfil |
| `auth_method` | Métodos de autenticação (Google/senha) |
| `plan` | Planos de assinatura |
| `company` | Empresas (vinculadas a um profile COMPANY) |
| `store` | Lojas (vinculadas a uma company) |
| `payment` | Pagamentos de planos |
| `pantry_item` | Itens no estoque doméstico |
| `pantry_product_setting` | Configuração de quantidade mínima por alimento |

### Regras de negócio

As regras vivem em funções + triggers, não na camada de aplicação:

- **`validate_profile_reference_type(tipo)`** — garante que `profile_id` de `pantry_item`, `pantry_product_setting`, `company` e `store` aponte para um profile do tipo esperado (`HOUSEHOLD`, `COMPANY`, `STORE`). Aplica via triggers de `BEFORE INSERT/UPDATE`.
- **`prevent_profile_type_change()`** — impede que o `type` de um profile seja alterado depois de criado.

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

## Em andamento / placeholders

- `script/03_bi_views/` — views de BI ainda não definidas.
- `script/04_monitoramento/script_dau.sql` — métrica de DAU, ainda sem conteúdo.
- `doc/` e `rpa/` — vazios, aguardando trabalho.
