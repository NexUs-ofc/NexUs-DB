# NexUs-DB

Banco de dados do NexUs — gestão de alimentos em geladeira, freezer e despensa. Este repositório contém o modelo relacional (PostgreSQL), a camada de dados do MongoDB, a carga de dados (dataload) e scripts auxiliares.

PostgreSQL MongoDB Python

## O que tem aqui

O repositório tem três frentes:

- **Schema SQL** — DDL, enums, funções e triggers do PostgreSQL, versionados sob `script/`.
- **Dataload** — gera e popula dados fictícios no PostgreSQL e no MongoDB (`script/dataload`).
- **Auxiliares** — views de BI, scripts de monitoramento e placeholders para trabalhos futuros.

```
NexUs-DB/
├── script/
│   ├── 01_ddl_estrutura/     # reset, tipos (enums), tabelas, índices
│   ├── 02_objetos_logicos/   # funções + triggers
│   ├── 03_bi_views/          # views de BI (a definir)
│   ├── 04_monitoramento/     # scripts de monitoramento
│   └── dataload/             # carga de dados (Postgres + Mongo)
├── doc/                      # documentação (a preencher)
├── rpa/                      # automação (a preencher)
├── requirements.txt
└── .env                      # credenciais (não versionado)
```

## Schema PostgreSQL

Os scripts em `script/01_ddl_estrutura/` e `script/02_objetos_logicos/` definem o banco. A ordem de aplicação é a numeração dos arquivos:

1. `reset.sql` — dropa tabelas e tipos existentes (CASCADE)
2. `001_tipos.sql` — enums
3. `002_tabelas.sql` — tabelas
4. `02_objetos_logicos/001_functions.sql` — funções
5. `02_objetos_logicos/002_triggers.sql` — triggers

### Enums

| Enum | Valores |
|------|---------|
| `profile_type_enum` | `HOUSEHOLD`, `ADMIN`, `COMPANY`, `STORE` |
| `profile_status_enum` | `ACTIVE`, `INACTIVE`, `BLOCKED` |
| `unit_of_measure_enum` | `g`, `kg`, `ml`, `l`, `unit` |
| `payment_status_enum` | `PENDING`, `PAID`, `OVERDUE`, `CANCELLED` |
| `auth_provider_enum` | `GOOGLE`, `PASSWORD` |

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

Nota sobre IDs: as tabelas usam `INTEGER PRIMARY KEY` sem `SERIAL` (o DDL foi desenhado para carga de dados). o próximo ID é obtido com `MAX(id)+1` no momento da inserção.

## Dataload

O dataload em `script/dataload/` aplica o schema e popula os dois bancos com dados fictícios determinísticos (seed fixo).

Dependências: `psycopg2-binary`, `pymongo`, `faker`, `faker_food`, `python-dotenv` (ver `requirements.txt`).

```bash
pip install -r requirements.txt
```

Comandos (rodar a partir da raiz `NexUs-DB/`):

```bash
python -m script.dataload.src.main init        # aplica as migrations
python -m script.dataload.src.main seed-sql    # popula o PostgreSQL
python -m script.dataload.src.main seed-mongo  # popula o MongoDB
python -m script.dataload.src.main all         # init + seed-sql + seed-mongo
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
- O schema assume um banco PostgreSQL com o schema `dataload` como `search_path` (as tools do dataload usam esse schema diretamente).

## Em andamento / placeholders

- `script/03_bi_views/` — views de BI ainda não definidas.
- `script/04_monitoramento/script_dau.sql` — métrica de DAU, ainda sem conteúdo.
- `script/01_ddl_estrutura/003_indices.sql` — índices adicionais pendentes (o TODO fica no próprio arquivo da migration).
- `doc/` e `rpa/` — vazios, aguardando trabalho.
