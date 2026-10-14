# RPA de migração (banco legado → banco novo)

Robô que move os dados do banco legado (tabelas `tb_*`) para o banco novo normalizado
do NexUs (schema das `migrations/`). É um ETL simples (extração, transformação e carga)
que pode ser executado várias vezes sem duplicar registros.

```
rpa/
├── src/
│   ├── main.py           # orquestra: conexões, etapas, transações, log e registro da execução
│   ├── etapas.py         # uma função por etapa: extrai do legado, transforma e carrega no novo
│   └── transformacao.py  # regras de conversão/validação (CEP, UF, telefone, e-mail, GTIN...)
└── logs/rpa.log          # gerado na execução (não versionado)
```

## Mapeamento

As etapas rodam nesta ordem (dependências das chaves estrangeiras do destino):

| Etapa | Legado | Novo | Regras |
|-------|--------|------|--------|
| `categorias` | `tb_categoria` | `category` | nome sem espaços extras; se o nome já existe no destino, reaproveita |
| `alimentos` | `tb_alimento` | `food` | `codigo_barras` → `gtin` quando é um GTIN válido (8, 12, 13 ou 14 dígitos); se o GTIN já existe, reaproveita o alimento. O legado não tem embalagem: `package_quantity = 1`, `unit_of_measure = 'unit'` |
| `usuarios` | `tb_usuario` + `tb_endereco` da 1ª `tb_casa` | `profile` (`HOUSEHOLD`) + `address` | e-mail em minúsculas; CEP com 8 dígitos; estado convertido para a sigla (`São Paulo` → `SP`). Usuário sem casa é rejeitado (o destino exige endereço para `HOUSEHOLD`) |
| `casas` | `tb_casa` | — | a casa não tem tabela no destino: passa a apontar para o profile do dono |
| `telefones` | `tb_telefone` (de usuário e de casa) | `profile_phone` | formato E.164; números sem DDI recebem `+55` |
| `itens_dispensa` | `tb_item_dispensa` | `pantry_item` | quantidade maior que zero |

Não são migradas as tabelas sem equivalente no banco novo: `tb_lista_compra`,
`tb_item_lista_compra`, `tb_alerta`, `tb_restricao_alimentar`, `tb_usuario_restricao`,
`tb_nutricao`, `tb_ia_evento`, `tb_ia_receita`, `tb_loja`, `tb_funcionario`,
`tb_fornecedor`, `tb_fornece`, `tb_produto`, `tb_cliente`, `tb_venda` e `tb_item_venda`.
Também não há destino para `tb_categoria.descricao`, `tb_usuario.preferencias_consumo`
e `tb_usuario.configuracao_alerta`.

## Integridade e idempotência

- O RPA cria no banco novo o schema `rpa` (fora das tabelas do app) com:
  - `rpa.mapeamento (entidade, id_legado, id_novo)`: o que já foi migrado;
  - `rpa.execucao`: início, fim, status (`SUCESSO`/`FALHA`), etapa da falha, mensagem e resumo.
- Cada etapa é **uma transação no banco novo**: os registros e o seu mapeamento são
  gravados juntos. Se a etapa falhar, nada dela fica gravado.
- O banco legado **só é lido**, em uma transação somente leitura (`REPEATABLE READ`), que
  garante um retrato consistente durante toda a execução. Como só um banco recebe escrita,
  não é necessária uma transação distribuída entre os dois bancos.
- Registros já presentes em `rpa.mapeamento` são pulados. Telefones usam a chave primária
  `(profile_id, phone)` com `ON CONFLICT DO NOTHING`.

## Tratamento de falhas

- **Registro inválido** (CEP, UF, e-mail, telefone ou quantidade inválidos, e-mail já
  cadastrado, dependência não migrada): só aquele registro é desfeito (savepoint), ele aparece
  no log como `rejeitado` com o motivo e a etapa continua. Na próxima execução ele é
  avaliado de novo, então basta corrigir o dado no legado e executar novamente.
- **Erro de infraestrutura** (conexão, permissão, tabela inexistente): a etapa em andamento
  sofre rollback, a execução para com código de saída `1` e `rpa.execucao` registra
  `FALHA` com a etapa e a mensagem. As etapas anteriores continuam gravadas.
  Corrija a causa e execute de novo: a migração é retomada sem duplicar nada.

## Configuração

O RPA usa o mesmo `.env` da raiz do repositório. O banco novo usa as variáveis `PG_*`,
as mesmas do dataload. O banco legado usa as variáveis `LEGADO_PG_*`:

```env
# Banco novo (destino), com o schema das migrations já aplicado
PG_HOST=localhost
PG_PORT=5432
PG_DATABASE=nexus
PG_USER=postgres
PG_PASSWORD=postgres

# Banco legado (origem): o usuário só precisa de permissão de leitura
LEGADO_PG_HOST=localhost
LEGADO_PG_PORT=5432
LEGADO_PG_DATABASE=nexus_legado
LEGADO_PG_USER=postgres
LEGADO_PG_PASSWORD=postgres
# LEGADO_PG_SSLMODE=require   # opcional
```

O usuário do banco novo precisa poder criar o schema `rpa` na primeira execução.

## Como executar

Aplique as migrations no banco novo (veja [migrations/README.md](../migrations/README.md)) e,
a partir da raiz `NexUs-DB/`, rode:

```bash
pip install -r requirements.txt
python -m rpa.src.main
```

Exemplo de saída:

```
[INFO] Execução 1 iniciada
[INFO] [categorias] concluída: 3 migrados, 0 já migrados, 1 rejeitados
[WARNING] tb_usuario id=6 rejeitado: usuário sem casa/endereço (obrigatório para HOUSEHOLD)
...
[INFO] Execução 1 concluída com sucesso
```

## Execução automática (GitHub Actions)

O workflow [`.github/workflows/rpa.yml`](../.github/workflows/rpa.yml) roda o RPA
**todo dia às 03:00 (Brasília)** e também pode ser disparado manualmente em
*Actions → RPA Migração Legado → Run workflow*.

- Como a carga é idempotente, cada execução migra só o que for novo no legado.
- `concurrency` impede duas execuções simultâneas.
- Se a migração falhar, o job fica vermelho e o GitHub avisa por e-mail. O `rpa.log` de cada
  execução fica disponível como artefato por 30 dias, e `rpa.execucao` guarda o histórico no banco.
- Execuções agendadas só rodam a partir da branch padrão (`main`), ou seja, depois do merge.

Configure em *Settings → Secrets and variables → Actions* os secrets:
`PG_HOST`, `PG_PORT`, `PG_DATABASE`, `PG_USER`, `PG_PASSWORD` (banco novo) e
`LEGADO_PG_HOST`, `LEGADO_PG_PORT`, `LEGADO_PG_DATABASE`, `LEGADO_PG_USER`,
`LEGADO_PG_PASSWORD` (banco legado). Os dois bancos precisam aceitar conexões vindas
dos runners do GitHub (sem lista restrita de IPs).

Para consultar o histórico:

```sql
SELECT id, inicio, fim, status, etapa, mensagem, resumo FROM rpa.execucao ORDER BY id DESC;
```
