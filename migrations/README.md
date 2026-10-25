# Migrations (Flyway)

O schema PostgreSQL do NexUs é versionado com [Flyway](https://flywaydb.org/), usando o
CLI standalone (este repositório é Python, não Java/Maven — não há dependência do Flyway
aqui, só os arquivos de migration e o CLI para aplicá-los).

## Arquivos

```
migrations/
├── V1__initial_schema.sql          # schema inicial completo (enums, tabelas, triggers)
├── V2__remove_microsoft_auth.sql    # remove MICROSOFT de auth_provider_enum
├── V3__drop_not_null_constraint.sql # profile.address_id passa a aceitar NULL
├── V4__add_geolocation_to_address.sql # adiciona latitude e longitude a address
├── V5__add_gtin_to_food.sql         # adiciona GTIN único a food
├── V6__use_gtin_as_food_unique_identifier.sql # remove a unicidade por dados descritivos
├── V7__require_address_for_household_and_store.sql # exige endereço para casas e lojas
├── V8__profile_restrictions_store_hours_billing_and_indexes.sql # perfil, horários, cobrança e índices
├── V9__food_image_url.sql           # imagem do produto trazida da api
├── V10__audit_triggers.sql          # auditoria de profile e payment (herança de tabelas)
└── V11__record_stock_movements_and_preserve_empty_items.sql # movimentos reais e lotes com saldo zero
```

O schema é compartilhado entre os serviços do NexUs, então o contrato do
banco passa a viver aqui, e não em cada serviço individualmente.

## Aplicando as migrations

Instale o [Flyway CLI](https://documentation.red-gate.com/fd/command-line-277579359.html).
No Windows, rode o executável diretamente a partir da raiz do repositório; assim,
não é necessário configurá-lo no `PATH`:

```powershell
& "$env:LOCALAPPDATA\Programs\Flyway\flyway-13.6.0\flyway.cmd" `
  -url="jdbc:postgresql://<host>:<port>/<database>" `
  -user="<usuario>" `
  -password="<senha>" `
  -locations="filesystem:migrations" migrate
```

### Banco novo (ambiente local/CI)

Sem schema prévio, basta rodar `migrate` diretamente — o Flyway cria a tabela de
histórico (`flyway_schema_history`) e aplica todas as migrations em sequência.

## Próximas migrations

Novas mudanças de schema devem ser adicionadas com a próxima versão disponível,
nunca alterando os arquivos já aplicados.

## V11 — movimentos de estoque

Permite saldo zero em pantry_item e registra CONSUMED ou DISCARDED com uma única quantity positiva em bi_hist.registro_estoque, ligada somente ao lote. O Core atualiza saldo e histórico na mesma transação e preserva lotes zerados fora das listagens.

Em bases com histórico antigo, a migration cria lotes encerrados para preservar os registros existentes, unifica as quantidades e converte os tipos. Quantidades inconsistentes com o tipo abortam a conversão. A perda monetária antiga é preservada; novas operações podem não ter estimated_loss.

Somente fato_movimento, dim_tempo e fato_estoque são adaptadas quando já existem. As fórmulas dos indicadores ficam para depois. Aplique a V11 antes de publicar o Core. Detalhes em doc/movimentacoes_estoque.md.

## V8 — perfil, lojas, cobrança e desempenho

A V8 adiciona profile.dietary_restrictions como TEXT[] NOT NULL com lista vazia
por padrão, e store.opening_time / store.closing_time como um único intervalo
local. O catálogo de restrições permanece no frontend. Os horários são
opcionais, mas precisam estar ambos ausentes ou ambos presentes, com o
fechamento posterior à abertura.

A restrição de endereço para HOUSEHOLD e STORE já está na V7; a V8 preserva
essa regra.

### Pré-requisitos e aplicação

- O servidor precisa disponibilizar pg_trgm e PostGIS; o usuário da migration
  precisa ter permissão para habilitar essas extensões.
- O Flyway aplica a V8 em transação; os índices são criados sem CONCURRENTLY.
  Planejar a janela de aplicação, pois a criação pode bloquear escritas.
- CREATE INDEX IF NOT EXISTS verifica nomes, não equivalência de definições:
  revisar previamente índices criados manualmente com esses mesmos nomes.
- O novo índice geográfico atende ST_DWithin usando a expressão
  ST_SetSRID(ST_MakePoint(longitude::double precision, latitude::double precision), 4326)::geography
  e o filtro de coordenadas não nulas. A query atual do Core com ACOS precisa
  ser substituída antes de aproveitar esse índice.

### Functions e procedures

| Objeto | Contrato |
| --- | --- |
| fn_get_expiring_products(início, fim) | Janela inclusiva; retorna somente itens de perfis ACTIVE, ordenados por validade e ID. |
| fn_get_items_below_minimum(profile_id opcional) | Considera validade hoje ou futura e validade ausente; inclui alimentos configurados sem estoque. |
| sp_generate_monthly_payments(data opcional, dia opcional, INOUT quantidade) | Dia padrão 10, aceito entre 1 e 28; uma cobrança por empresa/competência; inclui BLOCKED e exclui INACTIVE. |
| sp_update_overdue_payments(tolerância opcional, INOUT vencidos, INOUT bloqueados, INOUT reativados) | Tolerância não negativa; pagamentos vencem após o dia limite; contagens de bloqueio/reativação são de empresas. |

Quitar todas as pendências OVERDUE reativa a empresa e todas as suas lojas
BLOCKED, conforme a regra de que lojas só são bloqueadas por inadimplência.
Perfis INACTIVE são preservados. O job também bloqueia uma loja ACTIVE
encontrada sob uma empresa já BLOCKED que ainda tenha pagamentos OVERDUE.

A geração de cobranças mantém NOT EXISTS e ON CONFLICT DO NOTHING em conjunto
com o índice único de competência para evitar duplicação concorrente.
Agendamentos, cache, ranking e entrega de notificações permanecem tarefas
dos serviços.

A V8 mantém somente o índice trigram sobre LOWER(name). A IA já usa essa
expressão; a consulta do Core deve usar LOWER para aproveitar o mesmo índice
nas buscas da API.

## V10 — auditoria

Triggers `AFTER INSERT OR UPDATE OR DELETE` em `profile` e `payment` gravam OLD, NEW,
TG_OP e CURRENT_USER em `auditoria.log_profile` e `auditoria.log_payment`, filhas da tabela
`auditoria.log_alteracao` (herança). O usuário de cada serviço que escreve nessas tabelas
precisa de permissão no schema `auditoria`:

```sql
GRANT USAGE ON SCHEMA auditoria TO <usuario_do_servico>;
GRANT INSERT ON ALL TABLES IN SCHEMA auditoria TO <usuario_do_servico>;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA auditoria TO <usuario_do_servico>;
```
