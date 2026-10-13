-- =============================================================================
-- NexUs — Catálogo de metadados
-- Cria o schema `catalogo` e carrega a descrição de todas as tabelas, views e
-- collections do NexUs (PostgreSQL schemas public, bi e bi_hist + MongoDB).
--
--   catalogo.objeto  1 linha por tabela, view ou collection
--   catalogo.coluna  1 linha por coluna (PostgreSQL) ou campo (MongoDB)
--   catalogo.vw_dicionario_dados  as duas juntas, pronta para consulta
--
-- Pode rodar quantas vezes quiser: recria o schema catalogo do zero.
-- Não altera nenhuma tabela do app.
-- =============================================================================
BEGIN;

DROP SCHEMA IF EXISTS catalogo CASCADE;
CREATE SCHEMA catalogo;
COMMENT ON SCHEMA catalogo IS 'Catálogo de metadados do NexUs: descrição, tipo, chaves e classificação LGPD de cada dado.';

-- ------------------------------------------------------------------ tabelas
CREATE TABLE catalogo.objeto (
    id             SERIAL PRIMARY KEY,
    banco          VARCHAR(20)  NOT NULL CHECK (banco IN ('POSTGRESQL', 'MONGODB')),
    schema_nome    VARCHAR(63),
    objeto_nome    VARCHAR(63)  NOT NULL,
    tipo_objeto    VARCHAR(20)  NOT NULL CHECK (tipo_objeto IN ('TABELA', 'VIEW', 'COLLECTION')),
    descricao      TEXT         NOT NULL,
    CONSTRAINT uq_catalogo_objeto UNIQUE (banco, schema_nome, objeto_nome),
    CONSTRAINT ck_catalogo_objeto_schema CHECK ((banco = 'POSTGRESQL') = (schema_nome IS NOT NULL))
);

CREATE TABLE catalogo.coluna (
    id                  SERIAL PRIMARY KEY,
    objeto_id           INTEGER      NOT NULL REFERENCES catalogo.objeto(id) ON DELETE CASCADE,
    coluna_nome         VARCHAR(100) NOT NULL,
    posicao             INTEGER      NOT NULL CHECK (posicao > 0),
    tipo_dado           VARCHAR(100) NOT NULL,
    aceita_nulo         BOOLEAN      NOT NULL,
    valor_padrao        TEXT,
    chave               VARCHAR(20),
    referencia          VARCHAR(100),
    classificacao_lgpd  VARCHAR(10)  NOT NULL DEFAULT 'INTERNO'
                        CHECK (classificacao_lgpd IN ('INTERNO', 'PESSOAL', 'SENSIVEL', 'SIGILOSO')),
    descricao           TEXT         NOT NULL,
    CONSTRAINT uq_catalogo_coluna UNIQUE (objeto_id, coluna_nome),
    CONSTRAINT uq_catalogo_coluna_posicao UNIQUE (objeto_id, posicao)
);

COMMENT ON TABLE catalogo.objeto IS 'Tabelas, views e collections do NexUs.';
COMMENT ON COLUMN catalogo.objeto.id IS 'Identificador do objeto no catálogo.';
COMMENT ON COLUMN catalogo.objeto.banco IS 'POSTGRESQL ou MONGODB.';
COMMENT ON COLUMN catalogo.objeto.schema_nome IS 'Schema do PostgreSQL (public, bi, bi_hist); nulo para MongoDB.';
COMMENT ON COLUMN catalogo.objeto.objeto_nome IS 'Nome da tabela, view ou collection.';
COMMENT ON COLUMN catalogo.objeto.tipo_objeto IS 'TABELA, VIEW ou COLLECTION.';
COMMENT ON COLUMN catalogo.objeto.descricao IS 'O que o objeto guarda (e o grão, nas tabelas fato).';

COMMENT ON TABLE catalogo.coluna IS 'Colunas (PostgreSQL) e campos (MongoDB) de cada objeto do catálogo.';
COMMENT ON COLUMN catalogo.coluna.id IS 'Identificador da coluna no catálogo.';
COMMENT ON COLUMN catalogo.coluna.objeto_id IS 'Objeto dono da coluna (FK catalogo.objeto.id).';
COMMENT ON COLUMN catalogo.coluna.coluna_nome IS 'Nome da coluna; no MongoDB, campos aninhados usam ponto (ex.: items.food_id).';
COMMENT ON COLUMN catalogo.coluna.posicao IS 'Ordem da coluna no objeto.';
COMMENT ON COLUMN catalogo.coluna.tipo_dado IS 'Tipo do dado no banco de origem.';
COMMENT ON COLUMN catalogo.coluna.aceita_nulo IS 'Verdadeiro se a coluna aceita nulo (MongoDB: campo opcional).';
COMMENT ON COLUMN catalogo.coluna.valor_padrao IS 'Valor padrão (DEFAULT) da coluna.';
COMMENT ON COLUMN catalogo.coluna.chave IS 'PK, FK e/ou UK.';
COMMENT ON COLUMN catalogo.coluna.referencia IS 'Destino da FK (tabela.coluna). No MongoDB, referência lógica sem FK.';
COMMENT ON COLUMN catalogo.coluna.classificacao_lgpd IS 'INTERNO, PESSOAL (identifica pessoa), SENSIVEL (saúde/religião) ou SIGILOSO (credencial).';
COMMENT ON COLUMN catalogo.coluna.descricao IS 'Significado da coluna.';

-- ------------------------------------------------------------------ objetos

INSERT INTO catalogo.objeto (id, banco, schema_nome, objeto_nome, tipo_objeto, descricao) VALUES
    (1, 'POSTGRESQL', 'public', 'address', 'TABELA', 'Endereços de households, empresas e lojas. Usado na análise regional (cidade, UF, região).'),
    (2, 'POSTGRESQL', 'public', 'auth_method', 'TABELA', 'Formas de login do perfil: no máximo uma por provedor.'),
    (3, 'POSTGRESQL', 'public', 'category', 'TABELA', 'Domínio: categorias de alimentos (17 fixas, iguais às do supermercado).'),
    (4, 'POSTGRESQL', 'public', 'company', 'TABELA', 'Empresa cliente (B2B). Cada empresa é também um perfil COMPANY.'),
    (5, 'POSTGRESQL', 'public', 'food', 'TABELA', 'Catálogo de alimentos (SKU): produto + marca + embalagem, identificado pelo GTIN.'),
    (6, 'POSTGRESQL', 'public', 'pantry_item', 'TABELA', 'Itens na despensa, geladeira ou freezer do household hoje. Um registro por lote comprado.'),
    (7, 'POSTGRESQL', 'public', 'pantry_product_setting', 'TABELA', 'Estoque mínimo que o household quer manter de cada alimento (gera alerta de reposição).'),
    (8, 'POSTGRESQL', 'public', 'payment', 'TABELA', 'Cobranças mensais do plano de cada empresa.'),
    (9, 'POSTGRESQL', 'public', 'plan', 'TABELA', 'Domínio: planos de assinatura das empresas (Ceris, Enterprise, Exclusive).'),
    (10, 'POSTGRESQL', 'public', 'profile', 'TABELA', 'Perfil de acesso ao NexUs. O tipo define o papel e não pode mudar depois de criado (trg_profile_type_lock).'),
    (11, 'POSTGRESQL', 'public', 'profile_phone', 'TABELA', 'Telefones do perfil (0..N por perfil).'),
    (12, 'POSTGRESQL', 'public', 'store', 'TABELA', 'Loja (filial) de uma empresa. Cada loja é também um perfil STORE.'),
    (13, 'POSTGRESQL', 'bi', 'dim_alimento', 'VIEW', 'Dimensão alimento (food) com a categoria desnormalizada.'),
    (14, 'POSTGRESQL', 'bi', 'dim_empresa', 'VIEW', 'Dimensão empresa com o plano desnormalizado.'),
    (15, 'POSTGRESQL', 'bi', 'dim_localidade', 'VIEW', 'Dimensão localidade (address) sem rua, número nem CEP. sk_localidade = -1 é "não informado".'),
    (16, 'POSTGRESQL', 'bi', 'dim_perfil', 'VIEW', 'Dimensão perfil sem nome, e-mail ou telefone.'),
    (17, 'POSTGRESQL', 'bi', 'dim_tempo', 'VIEW', 'Dimensão calendário (1 linha por dia) do primeiro cadastro até 1 ano à frente. sk_data = -1 é "não informado".'),
    (18, 'POSTGRESQL', 'bi', 'fato_cadastro', 'VIEW', 'Fato cadastro. Grão: 1 perfil.'),
    (19, 'POSTGRESQL', 'bi', 'fato_estoque', 'VIEW', 'Fato estoque. Grão: 1 item hoje na despensa.'),
    (20, 'POSTGRESQL', 'bi', 'fato_estoque_minimo', 'VIEW', 'Fato estoque mínimo. Grão: household x alimento com mínimo > 0.'),
    (21, 'POSTGRESQL', 'bi', 'fato_movimento', 'VIEW', 'Fato movimento. Grão: 1 item consumido ou descartado (bi_hist.registro_estoque).'),
    (22, 'POSTGRESQL', 'bi', 'fato_pagamento', 'VIEW', 'Fato pagamento. Grão: 1 cobrança mensal.'),
    (23, 'POSTGRESQL', 'bi', 'kpi_d1_desperdicio_mensal', 'VIEW', 'D1: taxa de desperdício = expirados / (expirados + consumidos), por mês e região.'),
    (24, 'POSTGRESQL', 'bi', 'kpi_d3_d4_d8_validade_uf', 'VIEW', 'D3 (% vencidos), D4 (% a vencer em 7 dias) e D8 (% sem validade) dos itens na despensa, por UF.'),
    (25, 'POSTGRESQL', 'bi', 'kpi_d5_ranking_vencimento_uf', 'VIEW', 'D5: ranking de UFs por itens vencidos ou a vencer em 30 dias.'),
    (26, 'POSTGRESQL', 'bi', 'kpi_d6_estoque_minimo_uf', 'VIEW', 'D6: % de households com algum alimento abaixo do mínimo, por UF.'),
    (27, 'POSTGRESQL', 'bi', 'kpi_d7_vida_util_categoria', 'VIEW', 'D7: vida útil no cadastro (validade - entrada), por categoria.'),
    (28, 'POSTGRESQL', 'bi', 'kpi_d9_desperdicio_categoria', 'VIEW', 'D9: itens expirados da categoria / households que têm a categoria.'),
    (29, 'POSTGRESQL', 'bi', 'vw_kpi_cards', 'VIEW', 'Cards do dashboard: valor, meta, desvio e situação de D1-D9, financeiro (F1, F2) e base ativa (U1).'),
    (30, 'POSTGRESQL', 'bi', 'vw_volume_tabelas', 'VIEW', 'Teste de volume: registros por tabela e se atinge 500.'),
    (31, 'POSTGRESQL', 'bi_hist', 'registro_estoque', 'TABELA', 'Histórico de saída da despensa: 1 linha por item consumido ou descartado vencido.'),
    (32, 'MONGODB', NULL, 'recipes', 'COLLECTION', 'Receitas geradas pela IA ou cadastradas pelo usuário.'),
    (33, 'MONGODB', NULL, 'recipe_accounts', 'COLLECTION', 'Receitas salvas por household (relação N:N receita × perfil).'),
    (34, 'MONGODB', NULL, 'events', 'COLLECTION', 'Eventos planejados pelo household (churrasco, aniversário) com as receitas e o cálculo de ingredientes.'),
    (35, 'MONGODB', NULL, 'shopping_lists', 'COLLECTION', 'Listas de compras, avulsas ou geradas a partir de um evento.'),
    (36, 'MONGODB', NULL, 'records', 'COLLECTION', 'Movimentos de estoque do household. `item_consumed` e `item_expired` são os mesmos eventos que o'),
    (37, 'MONGODB', NULL, 'notifications', 'COLLECTION', 'Alertas do NexUs-Notify. Formato igual ao domínio `Notification` do serviço.'),
    (38, 'MONGODB', NULL, 'conversations', 'COLLECTION', 'Histórico das conversas com o assistente.'),
    (39, 'MONGODB', NULL, 'knowledge', 'COLLECTION', 'Fatos que a IA aprendeu sobre o household (gostos, acertos e erros de estimativa).'),
    (40, 'MONGODB', NULL, 'metrics', 'COLLECTION', 'Telemetria da IA: 1 requisição ao assistente.'),
    (41, 'MONGODB', NULL, 'tool_metrics', 'COLLECTION', 'Telemetria da IA: 1 chamada de ferramenta do assistente.'),
    (42, 'MONGODB', NULL, 'traces', 'COLLECTION', 'Telemetria da IA: 1 etapa (span) de execução.');

SELECT setval('catalogo.objeto_id_seq', (SELECT MAX(id) FROM catalogo.objeto));

-- public.address
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (1, 'id', 1, 'integer', FALSE, 'nextval(''address_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do endereço (serial).'),
    (1, 'neighborhood', 2, 'character varying(100)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Bairro.'),
    (1, 'street', 3, 'character varying(150)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Logradouro.'),
    (1, 'number', 4, 'character varying(10)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Número do imóvel (texto: aceita S/N, 12A).'),
    (1, 'cep', 5, 'character(8)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'CEP com 8 dígitos, sem máscara.'),
    (1, 'city', 6, 'character varying(100)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Cidade.'),
    (1, 'state', 7, 'character(2)', FALSE, NULL, NULL, NULL, 'INTERNO', 'UF com 2 letras maiúsculas. Ex.: SP.'),
    (1, 'latitude', 8, 'numeric(9,6)', TRUE, NULL, NULL, NULL, 'PESSOAL', 'Latitude em graus decimais (V4).'),
    (1, 'longitude', 9, 'numeric(9,6)', TRUE, NULL, NULL, NULL, 'PESSOAL', 'Longitude em graus decimais (V4).');

-- public.auth_method
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (2, 'id', 1, 'integer', FALSE, 'nextval(''auth_method_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do método de login (serial).'),
    (2, 'profile_id', 2, 'integer', FALSE, NULL, 'FK, UK', 'profile.id', 'INTERNO', 'Perfil que usa este login (FK profile.id, cascata).'),
    (2, 'provider', 3, 'auth_provider_enum', FALSE, NULL, 'UK', NULL, 'INTERNO', 'Provedor (auth_provider_enum).'),
    (2, 'credential', 4, 'character varying(255)', FALSE, NULL, NULL, NULL, 'SIGILOSO', 'Subject do Google ou hash da senha. Nunca expor.'),
    (2, 'created_at', 5, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Quando o método foi vinculado ao perfil.');

-- public.category
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (3, 'id', 1, 'integer', FALSE, 'nextval(''category_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da categoria (serial).'),
    (3, 'category_name', 2, 'character varying(100)', FALSE, NULL, 'UK', NULL, 'INTERNO', 'Nome da categoria, único. Ex.: Laticínios e Ovos.');

-- public.company
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (4, 'id', 1, 'integer', FALSE, 'nextval(''company_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da empresa (serial).'),
    (4, 'plan_id', 2, 'integer', FALSE, NULL, 'FK', 'plan.id', 'INTERNO', 'Plano atual da empresa (FK plan.id).'),
    (4, 'cnpj', 3, 'character(14)', FALSE, NULL, 'UK', NULL, 'INTERNO', 'CNPJ com 14 dígitos, sem máscara, único.'),
    (4, 'profile_id', 4, 'integer', FALSE, NULL, 'FK, UK', 'profile.id', 'INTERNO', 'Perfil COMPANY da empresa (FK profile.id, 1:1).');

-- public.food
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (5, 'id', 1, 'integer', FALSE, 'nextval(''food_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do alimento (serial).'),
    (5, 'name', 2, 'character varying(150)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome do produto. Ex.: Arroz branco tipo 1.'),
    (5, 'category_id', 3, 'integer', FALSE, NULL, 'FK', 'category.id', 'INTERNO', 'Categoria do alimento (FK category.id).'),
    (5, 'product_brand', 4, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Marca do produto; nulo para itens a granel.'),
    (5, 'package_quantity', 5, 'numeric(10,2)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade da embalagem, na unidade de unit_of_measure. Maior que zero.'),
    (5, 'unit_of_measure', 6, 'unit_of_measure_enum', FALSE, NULL, NULL, NULL, 'INTERNO', 'Unidade de package_quantity (unit_of_measure_enum).'),
    (5, 'gtin', 7, 'character varying(14)', TRUE, NULL, 'UK', NULL, 'INTERNO', 'Código de barras GTIN/EAN (até 14 dígitos), único. Identificador natural do produto desde a V6.');

-- public.pantry_item
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (6, 'id', 1, 'integer', FALSE, 'nextval(''pantry_item_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do item (serial).'),
    (6, 'food_id', 2, 'integer', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (FK food.id).'),
    (6, 'profile_id', 3, 'integer', FALSE, NULL, 'FK', 'profile.id', 'INTERNO', 'Household dono do item (FK profile.id, cascata).'),
    (6, 'quantity', 4, 'integer', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade de embalagens. Maior que zero.'),
    (6, 'expiry_date', 5, 'date', TRUE, NULL, NULL, NULL, 'INTERNO', 'Data de validade; nulo quando o produto não tem validade impressa (granel, feira).'),
    (6, 'created_at', 6, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Quando o item entrou na despensa (compra).');

-- public.pantry_product_setting
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (7, 'id', 1, 'integer', FALSE, 'nextval(''pantry_product_setting_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da configuração (serial).'),
    (7, 'food_id', 2, 'integer', FALSE, NULL, 'FK, UK', 'food.id', 'INTERNO', 'Alimento monitorado (FK food.id, cascata).'),
    (7, 'profile_id', 3, 'integer', FALSE, NULL, 'FK, UK', 'profile.id', 'INTERNO', 'Household (FK profile.id, cascata). Único por household e alimento.'),
    (7, 'minimum_quantity', 4, 'integer', FALSE, '0', NULL, NULL, 'INTERNO', 'Quantidade mínima de embalagens; 0 desliga o alerta.'),
    (7, 'created_at', 5, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data de criação da configuração.'),
    (7, 'updated_at', 6, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data da última alteração do mínimo.');

-- public.payment
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (8, 'id', 1, 'integer', FALSE, 'nextval(''payment_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da cobrança (serial).'),
    (8, 'due_date', 2, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Data de vencimento.'),
    (8, 'billing_period_start', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início do período cobrado (competência).'),
    (8, 'billing_period_end', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Fim do período cobrado; maior ou igual ao início.'),
    (8, 'payment_status', 5, 'payment_status_enum', FALSE, NULL, NULL, NULL, 'INTERNO', 'Situação da cobrança (payment_status_enum).'),
    (8, 'company_id', 6, 'integer', FALSE, NULL, 'FK', 'company.id', 'INTERNO', 'Empresa cobrada (FK company.id).'),
    (8, 'plan_id', 7, 'integer', FALSE, NULL, 'FK', 'plan.id', 'INTERNO', 'Plano vigente no período cobrado (FK plan.id); pode diferir do plano atual da empresa.'),
    (8, 'amount', 8, 'numeric(10,2)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Valor cobrado em R$.'),
    (8, 'created_at', 9, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data de emissão da cobrança.'),
    (8, 'updated_at', 10, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data da última mudança de situação.'),
    (8, 'paid_at', 11, 'timestamp without time zone', TRUE, NULL, NULL, NULL, 'INTERNO', 'Data e hora do pagamento; nulo enquanto não pago.');

-- public.plan
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (9, 'id', 1, 'integer', FALSE, 'nextval(''plan_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do plano (serial).'),
    (9, 'plan_price', 2, 'numeric(10,2)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Mensalidade em R$.'),
    (9, 'plan_name', 3, 'character varying(80)', FALSE, NULL, 'UK', NULL, 'INTERNO', 'Nome comercial do plano, único.'),
    (9, 'store_limit', 4, 'integer', FALSE, NULL, NULL, NULL, 'INTERNO', 'Máximo de lojas que a empresa pode cadastrar no plano.'),
    (9, 'description', 5, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Recursos incluídos no plano.'),
    (9, 'is_active', 6, 'boolean', FALSE, 'true', NULL, NULL, 'INTERNO', 'Plano disponível para venda.'),
    (9, 'created_at', 7, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data de criação do registro.'),
    (9, 'updated_at', 8, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data da última alteração do registro.');

-- public.profile
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (10, 'id', 1, 'integer', FALSE, 'nextval(''profile_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do perfil (serial). Referenciado também pelo MongoDB (household_id, account_id, profile_id).'),
    (10, 'address_id', 2, 'integer', TRUE, NULL, 'FK', 'address.id', 'INTERNO', 'Endereço do perfil (FK address.id). Obrigatório para HOUSEHOLD e STORE (V7); opcional para ADMIN e COMPANY.'),
    (10, 'email', 3, 'character varying(255)', FALSE, NULL, 'UK', NULL, 'PESSOAL', 'E-mail de login, único.'),
    (10, 'name', 4, 'character varying(150)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Nome da pessoa (HOUSEHOLD/ADMIN) ou razão social (COMPANY/STORE).'),
    (10, 'created_at', 5, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data e hora do cadastro.'),
    (10, 'type', 6, 'profile_type_enum', FALSE, NULL, NULL, NULL, 'INTERNO', 'Tipo do perfil (profile_type_enum). Imutável.'),
    (10, 'profile_image_url', 7, 'character varying(500)', TRUE, NULL, NULL, NULL, 'PESSOAL', 'URL da foto de perfil.'),
    (10, 'status', 8, 'profile_status_enum', FALSE, '''ACTIVE''::profile_status_enum', NULL, NULL, 'INTERNO', 'Situação do perfil (profile_status_enum). Padrão ACTIVE.'),
    (10, 'dietary_restriction', 9, 'text', TRUE, NULL, NULL, NULL, 'SENSIVEL', 'Restrições alimentares declaradas pelo household (alergias, intolerâncias, dietas, condições de saúde ou religiosas). Ex.: lactose, glúten, vegano. Nulo = não informou.');

-- public.profile_phone
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (11, 'profile_id', 1, 'integer', FALSE, NULL, 'PK, FK', 'profile.id', 'INTERNO', 'Perfil dono do telefone (FK profile.id, cascata).'),
    (11, 'phone', 2, 'character varying(16)', FALSE, NULL, 'PK', NULL, 'PESSOAL', 'Telefone no formato E.164: +, DDI e número, 8 a 15 dígitos.');

-- public.store
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (12, 'id', 1, 'integer', FALSE, 'nextval(''store_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da loja (serial).'),
    (12, 'cnpj', 2, 'character(14)', FALSE, NULL, 'UK', NULL, 'INTERNO', 'CNPJ da filial com 14 dígitos, sem máscara, único.'),
    (12, 'company_id', 3, 'integer', FALSE, NULL, 'FK', 'company.id', 'INTERNO', 'Empresa dona da loja (FK company.id, cascata).'),
    (12, 'profile_id', 4, 'integer', FALSE, NULL, 'FK, UK', 'profile.id', 'INTERNO', 'Perfil STORE da loja (FK profile.id, 1:1).');

-- bi.dim_alimento
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (13, 'sk_alimento', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave do alimento (= food.id).'),
    (13, 'alimento', 2, 'character varying(150)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Nome do produto.'),
    (13, 'marca', 3, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Marca.'),
    (13, 'embalagem', 4, 'numeric(10,2)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Quantidade da embalagem.'),
    (13, 'unidade', 5, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Unidade da embalagem.'),
    (13, 'descricao', 6, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Produto + marca + embalagem, para exibição.'),
    (13, 'categoria', 7, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Categoria do alimento.');

-- bi.dim_empresa
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (14, 'sk_empresa', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave da empresa (= company.id).'),
    (14, 'plano', 2, 'character varying(80)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Plano atual.'),
    (14, 'preco_plano', 3, 'numeric(10,2)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mensalidade do plano em R$.'),
    (14, 'limite_lojas', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Limite de lojas do plano.'),
    (14, 'qtd_lojas', 5, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Lojas cadastradas.');

-- bi.dim_localidade
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (15, 'sk_localidade', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave da localidade (= address.id).'),
    (15, 'cidade', 2, 'character varying', TRUE, NULL, NULL, NULL, 'INTERNO', 'Cidade.'),
    (15, 'uf', 3, 'bpchar', TRUE, NULL, NULL, NULL, 'INTERNO', 'UF.'),
    (15, 'regiao', 4, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região do IBGE derivada da UF.'),
    (15, 'latitude', 5, 'numeric', TRUE, NULL, NULL, NULL, 'PESSOAL', 'Latitude, para mapas.'),
    (15, 'longitude', 6, 'numeric', TRUE, NULL, NULL, NULL, 'PESSOAL', 'Longitude, para mapas.'),
    (15, 'geo_valida', 7, 'boolean', TRUE, NULL, NULL, NULL, 'INTERNO', 'Coordenada dentro do território brasileiro.');

-- bi.dim_perfil
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (16, 'sk_perfil', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave do perfil (= profile.id).'),
    (16, 'tipo', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Tipo do perfil.'),
    (16, 'status', 3, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Situação do perfil.'),
    (16, 'login', 4, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Primeiro provedor de login vinculado.'),
    (16, 'ano_mes_cadastro', 5, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mês do cadastro (AAAA-MM).'),
    (16, 'tempo_de_casa', 6, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Faixa de tempo desde o cadastro: 0-3, 3-6 ou 6+ meses.'),
    (16, 'origem', 7, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'APP (dado real) ou SIMULADO_BI (dataload BI, e-mail @bi.nexus.local).');

-- bi.dim_tempo
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (17, 'sk_data', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave da data no formato AAAAMMDD.'),
    (17, 'data', 2, 'date', TRUE, NULL, NULL, NULL, 'INTERNO', 'Data.'),
    (17, 'ano', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Ano.'),
    (17, 'mes', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mês (1-12).'),
    (17, 'ano_mes', 5, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Ano-mês no formato AAAA-MM.'),
    (17, 'trimestre', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Trimestre (1-4).'),
    (17, 'dia_semana', 7, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Dia da semana ISO (1 = segunda, 7 = domingo).'),
    (17, 'fim_de_semana', 8, 'boolean', TRUE, NULL, NULL, NULL, 'INTERNO', 'Verdadeiro para sábado e domingo.');

-- bi.fato_cadastro
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (18, 'sk_perfil', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_perfil.'),
    (18, 'sk_localidade', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade.'),
    (18, 'sk_data_cadastro', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: cadastro.'),
    (18, 'qtd', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Sempre 1 (contagem de cadastros).');

-- bi.fato_estoque
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (19, 'id_item', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'pantry_item.id (dimensão degenerada).'),
    (19, 'sk_alimento', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_alimento.'),
    (19, 'sk_perfil', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_perfil.'),
    (19, 'sk_localidade', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade.'),
    (19, 'sk_data_entrada', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: entrada na despensa.'),
    (19, 'sk_data_validade', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: validade (-1 sem validade).'),
    (19, 'quantidade', 7, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Embalagens.'),
    (19, 'tem_validade', 8, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se o item tem validade, 0 se não.'),
    (19, 'dias_ate_vencer', 9, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Dias até a validade (negativo = vencido).'),
    (19, 'vida_util_dias', 10, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Validade - data de entrada (D7).'),
    (19, 'status_validade', 11, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'SEM_VALIDADE, VENCIDO, VENCE_7D, VENCE_30D ou OK.');

-- bi.fato_estoque_minimo
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (20, 'sk_perfil', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_perfil.'),
    (20, 'sk_alimento', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_alimento.'),
    (20, 'sk_localidade', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade.'),
    (20, 'estoque', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Embalagens hoje na despensa.'),
    (20, 'minimo', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mínimo configurado.'),
    (20, 'abaixo_minimo', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se o estoque está abaixo do mínimo.');

-- bi.fato_movimento
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (21, 'id_movimento', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'registro_estoque.id (dimensão degenerada).'),
    (21, 'sk_alimento', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_alimento.'),
    (21, 'sk_perfil', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_perfil.'),
    (21, 'sk_localidade', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade.'),
    (21, 'sk_data_evento', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: consumo ou descarte.'),
    (21, 'sk_data_compra', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: compra.'),
    (21, 'sk_data_validade', 7, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: validade (-1 sem validade).'),
    (21, 'tipo_evento', 8, 'character varying(30)', TRUE, NULL, NULL, NULL, 'INTERNO', 'item_consumed ou item_expired.'),
    (21, 'expirado', 9, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se foi descartado vencido.'),
    (21, 'consumido', 10, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se foi consumido.'),
    (21, 'qtd_consumida', 11, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Embalagens consumidas.'),
    (21, 'qtd_descartada', 12, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Embalagens descartadas.'),
    (21, 'perda_estimada', 13, 'numeric(10,2)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Perda estimada em R$.'),
    (21, 'dias_em_casa', 14, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Dias entre a compra e o consumo/descarte.');

-- bi.fato_pagamento
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (22, 'id_pagamento', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'payment.id (dimensão degenerada).'),
    (22, 'sk_empresa', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_empresa.'),
    (22, 'sk_localidade', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade (endereço da empresa).'),
    (22, 'sk_data_competencia', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: início do período cobrado.'),
    (22, 'sk_data_pagamento', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: pagamento (-1 não pago).'),
    (22, 'status', 6, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Situação da cobrança.'),
    (22, 'valor', 7, 'numeric(10,2)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Valor em R$.'),
    (22, 'pago_no_prazo', 8, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se pago até o vencimento.');

-- bi.kpi_d1_desperdicio_mensal
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (23, 'ano_mes', 1, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mês do evento (nulo = todos).'),
    (23, 'regiao', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região (nulo = todas).'),
    (23, 'itens_expirados', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens descartados vencidos.'),
    (23, 'itens_consumidos', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens consumidos.'),
    (23, 'taxa_desperdicio_pct', 5, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D1 em %.'),
    (23, 'perda_estimada_rs', 6, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Perda estimada em R$.');

-- bi.kpi_d3_d4_d8_validade_uf
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (24, 'uf', 1, 'bpchar', TRUE, NULL, NULL, NULL, 'INTERNO', 'UF (nulo = Brasil).'),
    (24, 'regiao', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região.'),
    (24, 'itens', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens na despensa.'),
    (24, 'itens_com_validade', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens com validade.'),
    (24, 'itens_vencidos', 5, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens vencidos.'),
    (24, 'itens_vencem_7d', 6, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens que vencem em até 7 dias.'),
    (24, 'itens_sem_validade', 7, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens sem validade.'),
    (24, 'd3_vencidos_pct', 8, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D3 em %.'),
    (24, 'd4_vencem_7d_pct', 9, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D4 em %.'),
    (24, 'd8_sem_validade_pct', 10, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D8 em %.');

-- bi.kpi_d5_ranking_vencimento_uf
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (25, 'uf', 1, 'bpchar', TRUE, NULL, NULL, NULL, 'INTERNO', 'UF.'),
    (25, 'regiao', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região.'),
    (25, 'itens_vencidos', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens vencidos.'),
    (25, 'itens_vencem_30d', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens que vencem em até 30 dias.'),
    (25, 'itens_em_risco', 5, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Vencidos + a vencer em 30 dias.'),
    (25, 'ranking', 6, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'DENSE_RANK por itens em risco (1 = pior).');

-- bi.kpi_d6_estoque_minimo_uf
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (26, 'uf', 1, 'bpchar', TRUE, NULL, NULL, NULL, 'INTERNO', 'UF (nulo = Brasil).'),
    (26, 'regiao', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região.'),
    (26, 'households_com_minimo', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Households com mínimo configurado.'),
    (26, 'households_abaixo', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Households com algum item abaixo do mínimo.'),
    (26, 'd6_abaixo_minimo_pct', 5, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D6 em %.');

-- bi.kpi_d7_vida_util_categoria
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (27, 'categoria', 1, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Categoria (nulo = todas).'),
    (27, 'itens_com_validade', 2, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens com validade.'),
    (27, 'vida_util_media_dias', 3, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Média em dias.'),
    (27, 'vida_util_mediana_dias', 4, 'double precision', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mediana em dias.'),
    (27, 'vida_util_min_dias', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mínimo em dias.'),
    (27, 'vida_util_max_dias', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Máximo em dias.');

-- bi.kpi_d9_desperdicio_categoria
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (28, 'categoria', 1, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Categoria.'),
    (28, 'itens_expirados', 2, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens expirados da categoria.'),
    (28, 'households_com_categoria', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Households que compraram a categoria.'),
    (28, 'd9_indice_desperdicio', 4, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D9: itens expirados por household.'),
    (28, 'ranking', 5, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'DENSE_RANK pelo índice (1 = pior).');

-- bi.vw_kpi_cards
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (29, 'codigo', 1, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Código do KPI (D1..D9, F1, F2, U1).'),
    (29, 'kpi', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Nome do KPI.'),
    (29, 'valor', 3, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Valor atual.'),
    (29, 'unidade', 4, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Unidade do valor.'),
    (29, 'meta', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Meta (nulo = sem meta).'),
    (29, 'desvio', 6, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Valor - meta.'),
    (29, 'situacao', 7, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'DENTRO_DA_META, FORA_DA_META ou SEM_META.');

-- bi.vw_volume_tabelas
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (30, 'tabela', 1, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Tabela.'),
    (30, 'registros', 2, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Registros.'),
    (30, 'situacao', 3, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'OK, ABAIXO_DE_500, DOMINIO_FIXO ou LIMITADO_PELOS_PROFILES.');

-- bi_hist.registro_estoque
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (31, 'id', 1, 'integer', FALSE, 'nextval(''bi_hist.registro_estoque_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do registro (serial).'),
    (31, 'profile_id', 2, 'integer', FALSE, NULL, 'FK', 'profile.id', 'INTERNO', 'Household (FK profile.id, cascata).'),
    (31, 'food_id', 3, 'integer', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (FK food.id).'),
    (31, 'event_type', 4, 'character varying(30)', FALSE, NULL, NULL, NULL, 'INTERNO', 'item_consumed ou item_expired (mesmos valores de records no MongoDB).'),
    (31, 'event_date', 5, 'timestamp without time zone', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quando o item foi consumido ou descartado.'),
    (31, 'purchase_date', 6, 'timestamp without time zone', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quando o item entrou na despensa.'),
    (31, 'expiry_date', 7, 'date', TRUE, NULL, NULL, NULL, 'INTERNO', 'Validade do item; nulo se não tinha validade.'),
    (31, 'consumed_quantity', 8, 'integer', FALSE, '0', NULL, NULL, 'INTERNO', 'Embalagens consumidas (item_consumed).'),
    (31, 'discarded_quantity', 9, 'integer', FALSE, '0', NULL, NULL, 'INTERNO', 'Embalagens descartadas (item_expired).'),
    (31, 'estimated_loss', 10, 'numeric(10,2)', FALSE, '0', NULL, NULL, 'INTERNO', 'Perda estimada em R$ com o descarte.');

-- mongodb.recipes
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (32, '_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador da receita.'),
    (32, 'title', 2, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome da receita.'),
    (32, 'serving_size', 3, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Porções que a receita rende.'),
    (32, 'ingredients', 4, 'array<object>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ingredientes (3 a 8).'),
    (32, 'ingredients.food_id', 5, 'int', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (food.id).'),
    (32, 'ingredients.required_quantity', 6, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade com unidade. Ex.: 500g, 2kg.'),
    (32, 'ingredients.mandatory', 7, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ingrediente indispensável.'),
    (32, 'ingredients.possible_substitutes', 8, 'array<int>', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'food.id que podem substituir (0 a 2).'),
    (32, 'instructions', 9, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Modo de preparo.'),
    (32, 'is_liked', 10, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'Usuário marcou como favorita.'),
    (32, 'created_by', 11, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'ai ou user.');

-- mongodb.recipe_accounts
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (33, '_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    (33, 'id_recipe', 2, 'ObjectId', FALSE, NULL, 'FK', 'recipes._id', 'INTERNO', 'Receita (recipes._id).'),
    (33, 'id_account', 3, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    (33, 'created_at', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quando a receita foi salva.');

-- mongodb.events
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (34, '_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador do evento.'),
    (34, 'household_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household dono (profile.id).'),
    (34, 'title', 3, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Título.'),
    (34, 'description', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Descrição livre (pode citar restrições dos convidados).'),
    (34, 'date', 5, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Data e hora do evento.'),
    (34, 'duration', 6, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Duração em minutos.'),
    (34, 'local', 7, 'string', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Local (cidade/endereço livre).'),
    (34, 'qtd_people', 8, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Número de convidados.'),
    (34, 'recipes', 9, 'array<object>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Receitas do evento (1 a 3).'),
    (34, 'recipes.recipe_id', 10, 'ObjectId', FALSE, NULL, 'FK', 'recipes._id', 'INTERNO', 'Receita (recipes._id).'),
    (34, 'recipes.title', 11, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome da receita no evento.'),
    (34, 'recipes.ingredients', 12, 'array<object>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ingredientes calculados para o número de pessoas.'),
    (34, 'recipes.ingredients.food_id', 13, 'int', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (food.id).'),
    (34, 'recipes.ingredients.ingredient', 14, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome do ingrediente.'),
    (34, 'recipes.ingredients.total_quantity', 15, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade total com unidade.'),
    (34, 'recipes.ingredients.has_enough', 16, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'Despensa tem o suficiente.');

-- mongodb.shopping_lists
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (35, '_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    (35, 'household_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    (35, 'event_id', 3, 'ObjectId', TRUE, NULL, 'FK', 'events._id', 'INTERNO', 'Evento de origem (events._id).'),
    (35, 'title', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Título da lista.'),
    (35, 'items', 5, 'array<object>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Itens (2 a 6).'),
    (35, 'items.food_id', 6, 'int', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (food.id).'),
    (35, 'items.ingredient', 7, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome do item.'),
    (35, 'items.quantity', 8, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade com unidade.'),
    (35, 'items.purchased', 9, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'Item já comprado.');

-- mongodb.records
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (36, '_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    (36, 'account_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    (36, 'date', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quando o evento aconteceu.'),
    (36, 'event_type', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'item_consumed, item_expired, recipe_status_changed ou shopping_list_added.'),
    (36, 'details', 5, 'object', FALSE, NULL, NULL, NULL, 'INTERNO', 'Detalhes do evento.'),
    (36, 'details.food_id', 6, 'int', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (food.id).'),
    (36, 'details.discarded_quantity', 7, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Embalagens descartadas.'),
    (36, 'details.estimated_loss', 8, 'double', FALSE, NULL, NULL, NULL, 'INTERNO', 'Perda estimada em R$.');

-- mongodb.notifications
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (37, '_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    (37, 'profile_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Destinatário (profile.id).'),
    (37, 'type', 3, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'PRODUCT_EXPIRING ou UPCOMING_EVENT.'),
    (37, 'source_id', 4, 'string', FALSE, NULL, 'FK', 'pantry_item.id ou events._id', 'INTERNO', 'pantry_item.id ou events._id em texto.'),
    (37, 'alert_key', 5, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Evita alerta repetido para o mesmo perfil, tipo e origem.'),
    (37, 'title', 6, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Título.'),
    (37, 'message', 7, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Mensagem.'),
    (37, 'created_at', 8, 'date (UTC)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Envio.'),
    (37, 'read_at', 9, 'date (UTC) ou null', TRUE, NULL, NULL, NULL, 'INTERNO', 'Primeira leitura; null = não lida.');

-- mongodb.conversations
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (38, '_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    (38, 'account_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    (38, 'historico', 3, 'array<object>', FALSE, NULL, NULL, NULL, 'SENSIVEL', 'Mensagens; texto livre pode conter dado de saúde.'),
    (38, 'historico.role', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'user ou assistant.'),
    (38, 'historico.content', 5, 'string', FALSE, NULL, NULL, NULL, 'SENSIVEL', 'Texto da mensagem.'),
    (38, 'created_at', 6, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início da conversa.'),
    (38, 'updated_at', 7, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Última mensagem.');

-- mongodb.knowledge
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (39, '_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    (39, 'household_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    (39, 'source_agent', 3, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'chat, recipes, events ou stock.'),
    (39, 'knowledge_type', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'preference, recipe_feedback, event_estimation_error ou event_estimation_success.'),
    (39, 'fact', 5, 'string', FALSE, NULL, NULL, NULL, 'SENSIVEL', 'Fato aprendido, em texto livre.'),
    (39, 'context.origin_event_id', 6, 'ObjectId', TRUE, NULL, 'FK', 'events._id', 'INTERNO', 'Evento que originou o fato (events._id).'),
    (39, 'ai_guideline.identified_triggers', 7, 'array<string>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Gatilhos identificados.'),
    (39, 'ai_guideline.recommended_action', 8, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ação recomendada à IA.');

-- mongodb.metrics
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (40, 'trace_id', 1, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Identificador da requisição (8 caracteres).'),
    (40, 'route', 2, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Rota do agente: eventos, receitas, estoque ou conversa.'),
    (40, 'started_at', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início.'),
    (40, 'finished_at', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Fim.'),
    (40, 'duration_ms', 5, 'double', FALSE, NULL, NULL, NULL, 'INTERNO', 'Duração em ms.'),
    (40, 'tool_calls', 6, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ferramentas chamadas.'),
    (40, 'error', 7, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'A requisição falhou.');

-- mongodb.tool_metrics
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (41, 'trace_id', 1, 'string', FALSE, NULL, 'FK', 'metrics.trace_id', 'INTERNO', 'Requisição (metrics.trace_id).'),
    (41, 'tool_name', 2, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'get_stock, get_recipe, get_event ou create_shopping_list.'),
    (41, 'started_at', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início.'),
    (41, 'finished_at', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Fim.'),
    (41, 'duration_ms', 5, 'double', FALSE, NULL, NULL, NULL, 'INTERNO', 'Duração em ms.'),
    (41, 'success', 6, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'A chamada deu certo.');

-- mongodb.traces
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao) VALUES
    (42, 'trace_id', 1, 'string', FALSE, NULL, 'FK', 'metrics.trace_id', 'INTERNO', 'Requisição (metrics.trace_id).'),
    (42, 'span_name', 2, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Etapa: roteador, banco, ia ou integracao.'),
    (42, 'started_at', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início.'),
    (42, 'finished_at', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Fim.'),
    (42, 'duration_ms', 5, 'double', FALSE, NULL, NULL, NULL, 'INTERNO', 'Duração em ms.'),
    (42, 'extra', 6, 'object', FALSE, NULL, NULL, NULL, 'INTERNO', 'Atributos adicionais do span.');

-- ------------------------------------------------------------------ view
CREATE VIEW catalogo.vw_dicionario_dados AS
SELECT o.banco, o.schema_nome, o.objeto_nome, o.tipo_objeto, o.descricao AS descricao_objeto,
       c.posicao, c.coluna_nome, c.tipo_dado, c.aceita_nulo, c.valor_padrao, c.chave, c.referencia,
       c.classificacao_lgpd, c.descricao AS descricao_coluna
FROM catalogo.objeto o
JOIN catalogo.coluna c ON c.objeto_id = o.id;

COMMENT ON VIEW catalogo.vw_dicionario_dados IS 'Dicionário de dados completo: uma linha por coluna, com o objeto dono.';

COMMIT;

-- Exemplos de consulta:
--   SELECT * FROM catalogo.vw_dicionario_dados WHERE objeto_nome = 'profile' ORDER BY posicao;
--   SELECT banco, objeto_nome, coluna_nome FROM catalogo.vw_dicionario_dados
--    WHERE classificacao_lgpd IN ('SENSIVEL', 'SIGILOSO');
--   SELECT banco, tipo_objeto, COUNT(*) FROM catalogo.objeto GROUP BY 1, 2;
