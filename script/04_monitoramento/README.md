# Monitoramento

## DAU (Daily Active Users)

`script_dau.sql` cria no schema `public` a estrutura que registra os usuários ativos por dia.
É um script SQL puro: rodar no pgAdmin (Query Tool) ou no `psql`,
no banco do app, **depois** das migrations. É idempotente — pode ser executado de novo sem erro.

| Objeto | Tipo | Finalidade |
|---|---|---|
| `daily_active_users` | tabela | 1 linha por usuário (`profile`) por dia. PK composta `(activity_date, user_id)` |
| `register_daily_activity(user_id, [data])` | função | registra o acesso com `INSERT ... ON CONFLICT DO NOTHING`; retorna `TRUE` no 1º acesso do dia |
| `vw_dau` | view | quantidade de usuários ativos por dia |

Regras:

- `user_id` referencia `profile(id)` com `ON DELETE CASCADE` (apagar o profile apaga o histórico de DAU).
- O dia é calculado no fuso `America/Sao_Paulo`, não em UTC.
- Chamadas repetidas ou simultâneas no mesmo dia não duplicam linhas nem geram erro.
- O parâmetro de data é opcional e serve só para backfill/testes.

### Executando

pgAdmin: abra o Query Tool no banco do app, carregue `script_dau.sql` e execute (F5).

psql (a partir da raiz `NexUs-DB/`):

```bash
psql -h <host> -p <port> -U <usuario> -d <database> -v ON_ERROR_STOP=1 -f script/04_monitoramento/script_dau.sql
```

### Registrando o acesso

Para registrar o acesso de um usuário no dia, chame a função:

```sql
SELECT register_daily_activity(:profile_id);
```

Em Python, pela conexão do projeto (`PostgresConnection`):

```python
pg = PostgresConnection()
try:
    pg.register_daily_activity(profile_id)
finally:
    pg.close()
```

Pela linha de comando (útil para testes e RPA):

```bash
python -m script.dataload.src.main register-dau --profile-id 1
```

### Consultas

```sql
SELECT * FROM vw_dau ORDER BY activity_date DESC;

-- DAU por tipo de perfil nos últimos 30 dias
SELECT d.activity_date, p.type, COUNT(*) AS dau
  FROM daily_active_users d
  JOIN profile p ON p.id = d.user_id
 WHERE d.activity_date >= CURRENT_DATE - 30
 GROUP BY d.activity_date, p.type
 ORDER BY d.activity_date DESC, p.type;
```
