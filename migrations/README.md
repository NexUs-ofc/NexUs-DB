# Migrations (Flyway)

O schema PostgreSQL do NexUs é versionado com [Flyway](https://flywaydb.org/), usando o
CLI standalone (este repositório é Python, não Java/Maven — não há dependência do Flyway
aqui, só os arquivos de migration e o CLI para aplicá-los).

## Arquivos

```
migrations/
├── V1__initial_schema.sql          # schema inicial completo (enums, tabelas, triggers)
├── V2__remove_microsoft_auth.sql   # remove MICROSOFT de auth_provider_enum
└── V3__drop_not_null_constraint.sql # profile.address_id passa a aceitar NULL
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
histórico (`flyway_schema_history`) e aplica V1, V2 e V3 em sequência.

## Próximas migrations

Novas mudanças de schema devem ser adicionadas como `V4__descricao.sql`,
`V5__descricao.sql` etc., nunca alterando os arquivos já aplicados.
