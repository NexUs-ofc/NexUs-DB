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
│   │   ├── mongo_ids.py     # ObjectIds gerados para cada carga do Mongo
│   │   ├── rng.py           # Faker com seed fixo (+ FoodProvider)
│   │   └── schemas/         # dataclasses das entidades (com to_dict)
│   ├── factories/           # gera os dados (objetos/dicts)
│   │   ├── base.py          # helper to_dicts
│   │   ├── catalog.py       # category, food
│   │   ├── address.py       # address
│   │   ├── account.py       # profile, profile_phone, auth_method
│   │   ├── billing.py       # plan, company, store, payment
│   │   ├── pantry.py        # pantry_item
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

Requer Python 3.11+ (usa `datetime.UTC` e `@dataclass(kw_only=True)`).

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

# Permite reiniciar os dados SQL locais com --reset
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

Para apagar os dados controlados pelo dataload e reiniciar os IDs do PostgreSQL:

```env
DATALOAD_ALLOW_RESET=true
```

```bash
python -m script.dataload.src.main all --reset
```

O modo `--reset` é destrutivo para o PostgreSQL e deve ser habilitado somente em ambientes locais ou de teste. No MongoDB, somente `metrics`, `records`, `tool_metrics` e `traces` são recriadas. Sem `DATALOAD_ALLOW_RESET=true`, o comando é recusado.

## O que é inserido

### PostgreSQL

Ordem de inserção (seguindo as chaves estrangeiras):

1. `category`, `plan` (dados fixos do `seed.py`)
2. `address`, `food`
3. `profile`
4. `profile_phone`, `auth_method`
5. `company`, `store`, `payment`
6. `pantry_item`

A carga do PostgreSQL ocorre em uma única transação. Se qualquer inserção falhar, todas as alterações da execução são revertidas.

### MongoDB

| Collection | Carga normal | Com `--reset` |
|------------|--------------|---------------|
| `metrics` | recria | recria |
| `records` | recria | recria |
| `tool_metrics` | recria | recria |
| `traces` | recria | recria |
| `recipes` | insere | insere |
| `events` | insere | insere |
| `recipe_accounts` | insere | insere |
| `conversations` | insere | insere |
| `knowledge` | insere | insere |
| `shopping_lists` | insere | insere |
| `notifications` | insere | insere |

`recipes` e `events` recebem novos ObjectIds em cada execução. Assim, novos documentos podem ser inseridos sem apagar os existentes, e as referências criadas na mesma carga permanecem consistentes.

Durante o reset, somente as collections legadas autorizadas com o prefixo `MONGO_` são removidas.

### Notificações

A collection `notifications` usa os mesmos campos do domínio `Notification` do NexUs-Notify:

| Campo | Tipo no MongoDB | Descrição |
|-------|-----------------|-----------|
| `_id` | ObjectId | Identificador gerado automaticamente pelo MongoDB. |
| `profile_id` | int | ID do profile destinatário da notificação. |
| `type` | string | Tipo: `PRODUCT_EXPIRING` ou `UPCOMING_EVENT`. |
| `source_id` | string | Identificador de exemplo do item da despensa ou ObjectId do evento convertido para string. |
| `alert_key` | string | Identifica o alerta para evitar notificações repetidas para o mesmo profile, tipo e origem. |
| `title` | string | Título da notificação. |
| `message` | string | Mensagem da notificação. |
| `created_at` | date | Data de criação em UTC. |
| `read_at` | date ou null | Data da primeira leitura; `null` indica uma notificação não lida. |

A carga gera 40 notificações com os dois tipos e exemplos lidos e não lidos. Cada execução usa chaves `seed:<ObjectId da carga>:<posição>` para permitir inserções incrementais sem conflito no índice único de alertas. Essas chaves são exemplos do dataload; as regras de geração do Notify definem as chaves dos alertas reais.

Cada execução insere novas notificações sem apagar as existentes, inclusive com `--reset`. A referência `profile_id` usa os IDs de household da carga SQL; o MongoDB não aplica chave estrangeira para o PostgreSQL. Os IDs numéricos de itens são exemplos e não garantem associação com um item de uma carga SQL anterior.

O Notify calcula o estado de leitura a partir de `read_at`, sem persistir `is_read` ou `priority`. O serviço define um índice único em `(profile_id, type, source_id, alert_key)` e um índice em `(profile_id, created_at DESC)`.

## Perfil BI

Acrescenta ~12 meses de uso simulado **no mesmo banco do app**, **somente no PostgreSQL**
(não grava nada no MongoDB), com ~500 registros verossímeis por tabela e variação
suficiente para os KPIs de desperdício D1, D3–D5 e D7–D9 do star schema.

```
python -m script.dataload.src.main all --perfil bi
```

Depois rode `script/03_bi_views/datamart_estrela.sql` no pgAdmin para recriar as views.

- Não apaga dados do app: cada execução remove e recria só os próprios dados
  (perfis com e-mail `@bi.nexus.local`, em cascata). Também remove o catálogo de execuções
  anteriores do BI que não estiver em uso.
- IDs vêm das sequences do banco, então não conflitam com o que o app grava.
- O histórico de consumo/descarte (`CONSUMED` / `DISCARDED`) fica em
  `bi_hist.registro_estoque`, criada pela V11. O Core grava movimentos reais; esta carga grava simulações.
- Cada movimento simulado aponta para um lote preservado em `pantry_item` com saldo zero.

| Tabela | Registros | Como é gerado |
|---|---|---|
| `food` | 520 | 70 produtos × marcas × embalagens, EAN-13 válido (prefixo `78991`) |
| `address` / `profile` | 520 | 380 households, 55 empresas, 85 lojas em 60 cidades das 27 UFs |
| `profile_phone` | ~560 | celular com DDD da UF + fixo para parte dos perfis |
| `auth_method` | ~545 | Google/senha; alguns vinculam os dois |
| `payment` | ~565 | mensalidades desde o cadastro; bons e maus pagadores |
| `pantry_item` | ~1040 | ~520 lotes disponíveis e ~520 lotes encerrados vinculados ao histórico |
| `bi_hist.registro_estoque` | 520 | itens consumidos ou descartados nos últimos 12 meses |
| `company` / `store` | 55 / 85 | cada uma também é um profile, então dividem os 520 com os households |
| `category` / `plan` | 17 / 3 | tabelas de domínio fixas |

A simulação gera mais eventos e reduz `pantry_item` e o histórico
por amostra aleatória até `ALVO` (520), o que preserva as proporções dos KPIs.
Para mudar o volume, altere `ALVO` e `VOL` em `src/bi.py`.

Variação simulada:
- Desperdício por categoria (`DESPERDICIO`: FLV e padaria vencem mais; enlatados e grãos quase nunca),
  por região (`DESPERDICIO_REGIAO`: maior no Norte, menor no Sul), por household (descuido individual,
  quem mora sozinho desperdiça mais) e ao longo do tempo (quem usa o app há mais meses desperdiça menos).
- Itens sem validade (`SEM_VALIDADE`): hortifrúti a granel, pão francês etc.
- Preferência de categorias por região (`PREFERENCIA_REGIAO`) e tamanho da casa (1 a 6 moradores).
- Opcional: `BI_DATA_REF=AAAA-MM-DD` fixa a "data de hoje" da simulação.
- Código: `src/bi.py`.

## Dados determinísticos

- `SEED` em `config.py` + `Faker.seed(SEED)` fazem os dados repetirem a cada execução.
- Os ObjectIds do Mongo são renovados em cada execução para permitir inserções incrementais. Dentro da mesma carga, `events`, `shopping_lists` e `knowledge` usam os IDs recém-gerados.

## Quantidades (TAMANHOS)

| Entidade | Quantidade |
|----------|-----------|
| food | 40 |
| address | 50 |
| profile | 123 (100 household + 10 company + 10 store + 3 admin) |
| company / store | 10 |
| payment | 30 |
| pantry_item | 150 |
| recipe / event | 30 / 40 |
| knowledge | 30 |
| record | 60 |
| shopping_list | 40 |
| notification | 40 |
| metric / tool_metric / trace | 20 / 30 / 20 |

As quantidades ficam em `src/config.py` (dict `TAMANHOS`).
