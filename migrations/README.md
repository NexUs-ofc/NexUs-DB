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

Esses 3 arquivos são os mesmos que já existiam (e já foram aplicados) no repositório
`NexUs-Auth` — o schema é compartilhado entre os serviços do NexUs, então o contrato do
banco passa a viver aqui, e não em cada serviço individualmente.

## Aplicando as migrations

Instale o [Flyway CLI](https://documentation.red-gate.com/fd/command-line-184127404.html)
e rode a partir da raiz do repositório:

```bash
flyway -url=jdbc:postgresql://<host>:<port>/<database> \
       -user=<usuario> \
       -password=<senha> \
       -locations=filesystem:migrations \
       migrate
```

### Banco já existente (produção/QA)

As 3 migrations acima **já foram executadas manualmente** nesses ambientes antes da
adoção do Flyway. Rodar `migrate` direto falharia (as tabelas já existem). Nesse caso,
faça o baseline primeiro — uma única vez, por ambiente — para o Flyway marcar essas 3
versões como já aplicadas sem tentar reexecutá-las:

```bash
flyway -url=jdbc:postgresql://<host>:<port>/<database> \
       -user=<usuario> \
       -password=<senha> \
       -locations=filesystem:migrations \
       -baselineVersion=3 \
       baseline
```

A partir daí, `flyway migrate` funciona normalmente para qualquer migration `V4__` em
diante.

### Banco novo (ambiente local/CI)

Sem schema prévio, basta rodar `migrate` diretamente — o Flyway cria a tabela de
histórico (`flyway_schema_history`) e aplica V1, V2 e V3 em sequência.

## Próximas migrations

Novas mudanças de schema devem ser adicionadas como `V4__descricao.sql`,
`V5__descricao.sql` etc., nunca alterando os arquivos já aplicados.
