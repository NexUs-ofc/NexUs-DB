# Dataload

Carga de dados do NexUs-DB. Popula o PostgreSQL e o MongoDB com dados fictícios após a aplicação das migrations. Os dados são determinísticos e podem ser recriados com o modo `--reset`.

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

# Permite apagar e recriar os dados locais com --reset
DATALOAD_ALLOW_RESET=false
```

O `config.py` chama `load_dotenv()`, que procura o `.env` no diretório de trabalho. Rode os comandos a partir de `NexUs-DB/`.

## Como rodar

Aplique o schema com Flyway antes (veja [migrations/README.md](../../migrations/README.md)).
A partir da raiz `NexUs-DB/`:

```bash
python -m script.dataload.src.main seed-sql
python -m script.dataload.src.main seed-mongo
python -m script.dataload.src.main all
python -m script.dataload.src.main all --reset
```

| Comando | Ação |
|---------|------|
| `seed-sql` | gera e insere os dados no PostgreSQL |
| `seed-mongo` | gera e insere os documentos no MongoDB |
| `all` | `seed-sql` + `seed-mongo` |

### Recriando os dados locais

Para apagar os dados controlados pelo dataload, reiniciar os IDs do PostgreSQL e recriar as collections do MongoDB:

```env
DATALOAD_ALLOW_RESET=true
```

```bash
python -m script.dataload.src.main all --reset
```

O modo `--reset` é destrutivo e deve ser habilitado somente em ambientes locais ou de teste. Sem `DATALOAD_ALLOW_RESET=true`, o comando é recusado.

## O que é inserido

### PostgreSQL

Ordem de inserção (seguindo as chaves estrangeiras):

1. `category`, `plan` (dados fixos do `seed.py`)
2. `address`, `food`
3. `profile`
4. `profile_phone`, `auth_method`
5. `company`, `store`, `payment`
6. `pantry_item`, `pantry_product_setting`

A carga do PostgreSQL ocorre em uma única transação. Se qualquer inserção falhar, todas as alterações da execução são revertidas.

### MongoDB

| Collection | Carga normal | Com `--reset` |
|------------|--------------|---------------|
| `metrics` | recria | recria |
| `records` | recria | recria |
| `tool_metrics` | recria | recria |
| `traces` | recria | recria |
| `recipes` | insere | recria |
| `events` | insere | recria |
| `recipe_accounts` | insere | recria |
| `conversations` | insere | recria |
| `knowledge` | insere | recria |
| `shopping_lists` | insere | recria |

Use `--reset` para repetir a carga completa. `recipes` e `events` possuem `_id` determinístico e não podem ser inseridas novamente sem a limpeza anterior.

Durante o reset, collections legadas com o prefixo `MONGO_` também são removidas.

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
