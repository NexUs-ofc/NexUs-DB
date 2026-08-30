# Dataload

Carga de dados do NexUs-DB. Aplica o schema SQL no PostgreSQL e popula os dois bancos com dados fictícios. Os dados são determinísticos (seed fixo), então rodar de novo produz o mesmo resultado.

## Estrutura

```
dataload/
├── src/
│   ├── main.py              # entrypoint (comandos via argparse)
│   ├── config.py            # TAMANHOS, SEED, get_env
│   ├── seed.py              # dados fixos: categories, plans, food_names
│   ├── core/
│   │   ├── ids.py           # quantidades e ranges de IDs fixos
│   │   ├── mongo_ids.py     # ObjectIds determinísticos do Mongo
│   │   ├── rng.py           # Faker com seed fixo (+ FoodProvider)
│   │   └── schemas/         # dataclasses das entidades (com to_dict)
│   ├── factories/           # gera os dados (objetos/dicts)
│   │   ├── base.py          # helper to_dicts
│   │   ├── catalog.py       # category, food
│   │   ├── address.py       # address
│   │   ├── account.py       # profile, profile_phone, auth_method
│   │   ├── billing.py       # plan, company, store, payment
│   │   ├── pantry.py        # pantry_item, pantry_product_setting
│   │   └── home.py          # collections do Mongo
│   ├── seeders/             # insere no banco
│   │   ├── postgres_seeder.py
│   │   └── mongo_seeder.py
│   └── db/                  # conexões
│       ├── postgres.py
│       ├── mongo.py
│       └── migration.py
```

As factories só criam os dados; os seeders fazem os inserts (sabem as tabelas e a ordem das chaves estrangeiras); o `main.py` só orquestra os comandos.

## Instalação

```bash
pip install -r requirements.txt
```

Dependências: `psycopg2-binary`, `pymongo`, `faker`, `faker_food`, `python-dotenv`.

Requer Python 3.10+ (usa `@dataclass(kw_only=True)`).

## Configuração (.env)

O `.env` fica na raiz do repositório (`NexUs-DB/.env`):

```env
# PostgreSQL
PG_HOST=localhost
PG_PORT=5432
PG_DATABASE=nexus
PG_USER=postgres
PG_PASSWORD=postgres

# MongoDB
MONGO_URI=mongodb://localhost:27017
MONGO_DB=nexus
```

O `config.py` chama `load_dotenv()`, que procura o `.env` no diretório de trabalho. Rode os comandos a partir de `NexUs-DB/`.

## Como rodar

A partir da raiz `NexUs-DB/`:

```bash
python -m script.dataload.src.main init
python -m script.dataload.src.main seed-sql
python -m script.dataload.src.main seed-mongo
python -m script.dataload.src.main all
```

| Comando | Ação |
|---------|------|
| `init` | aplica as migrations (script SQL) no PostgreSQL |
| `seed-sql` | gera e insere os dados no PostgreSQL |
| `seed-mongo` | gera e insere os documentos no MongoDB |
| `all` | `init` + `seed-sql` + `seed-mongo` |

## O que é inserido

### PostgreSQL

Ordem de inserção (seguindo as chaves estrangeiras):

1. `category`, `plan` (dados fixos do `seed.py`)
2. `address`, `food`
3. `profile`
4. `profile_phone`, `auth_method`
5. `company`, `store`, `payment`
6. `pantry_item`, `pantry_product_setting`

### MongoDB

| Collection | Drop antes do insert? |
|------------|------------------------|
| `MONGO_metrics` | sim |
| `MONGO_records` | sim |
| `MONGO_tool_metrics` | sim |
| `MONGO_traces` | sim |
| `MONGO_recipes` | não |
| `MONGO_events` | não |
| `MONGO_recipe_accounts` | não |
| `MONGO_conversations` | não |
| `MONGO_knowledge` | não |
| `MONGO_shopping_lists` | não |

As collections sem drop não apagam o que já existe; só acumulam os novos documentos a cada execução. Isso vale para: recipes, events, recipe_accounts, conversations, knowledge e shopping_lists.

## Dados determinísticos

- `SEED` em `config.py` + `Faker.seed(SEED)` fazem os dados repetirem a cada execução.
- Os ObjectIds do Mongo (`RECIPE_OIDS`, `EVENT_OIDS` em `core/mongo_ids.py`) também são fixos, então `events`, `shopping_lists` e `knowledge` referenciam sempre as mesmas receitas/eventos.

## Quantidades (TAMANHOS)

| Entidade | Quantidade |
|----------|-----------|
| food | 40 |
| address | 50 |
| profile | 123 (100 household + 10 company + 10 store + 3 admin) |
| company / store | 10 |
| payment | 30 |
| pantry_item | 150 |
| pantry_product_setting | 120 |
| recipe / event | 30 / 40 |
| knowledge | 30 |
| record | 60 |
| shopping_list | 40 |
| metric / tool_metric / trace | 20 / 30 / 20 |

As quantidades ficam em `src/config.py` (dict `TAMANHOS`).
