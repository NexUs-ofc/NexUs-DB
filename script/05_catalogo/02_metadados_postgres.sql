-- =============================================================================
-- NexUs — Catálogo de metadados (2/3): tabelas e views do PostgreSQL
-- Migrations V1-V9 (inclui schema auditoria), monitoramento (DAU) e schemas bi e bi_hist (data mart).
-- Pode rodar de novo quando quiser: apaga e recarrega só os metadados do PostgreSQL.
-- Requer 01_estrutura.sql já executado.
-- =============================================================================
BEGIN;

DELETE FROM catalogo.objeto WHERE banco = 'POSTGRESQL';  -- as colunas saem em cascata

-- ------------------------------------------------------------------ objetos
INSERT INTO catalogo.objeto (banco, schema_nome, objeto_nome, tipo_objeto, descricao) VALUES
    ('POSTGRESQL', 'public', 'address', 'TABELA', 'Endereços de households, empresas e lojas. Usado na análise regional (cidade, UF, região).'),
    ('POSTGRESQL', 'public', 'auth_method', 'TABELA', 'Formas de login do perfil: no máximo uma por provedor.'),
    ('POSTGRESQL', 'public', 'daily_active_users', 'TABELA', 'Monitoramento (DAU): 1 linha por usuário (profile) ativo por dia. Alimentada por register_daily_activity(); criada por script/04_monitoramento/script_dau.sql, fora do Flyway.'),
    ('POSTGRESQL', 'public', 'vw_dau', 'VIEW', 'Monitoramento: quantidade de usuários ativos (DAU) por dia.'),
    ('POSTGRESQL', 'public', 'category', 'TABELA', 'Domínio: categorias de alimentos (17 fixas, iguais às do supermercado).'),
    ('POSTGRESQL', 'public', 'company', 'TABELA', 'Empresa cliente (B2B). Cada empresa é também um perfil COMPANY.'),
    ('POSTGRESQL', 'public', 'food', 'TABELA', 'Catálogo de alimentos (SKU): produto + marca + embalagem, identificado pelo GTIN.'),
    ('POSTGRESQL', 'public', 'pantry_item', 'TABELA', 'Itens na despensa, geladeira ou freezer do household hoje. Um registro por lote comprado.'),
    ('POSTGRESQL', 'public', 'pantry_product_setting', 'TABELA', 'Estoque mínimo que o household quer manter de cada alimento (gera alerta de reposição).'),
    ('POSTGRESQL', 'public', 'payment', 'TABELA', 'Cobranças mensais do plano de cada empresa.'),
    ('POSTGRESQL', 'public', 'plan', 'TABELA', 'Domínio: planos de assinatura das empresas (Ceris, Enterprise, Exclusive).'),
    ('POSTGRESQL', 'public', 'profile', 'TABELA', 'Perfil de acesso ao NexUs. O tipo define o papel e não pode mudar depois de criado (trg_profile_type_lock).'),
    ('POSTGRESQL', 'public', 'profile_phone', 'TABELA', 'Telefones do perfil (0..N por perfil).'),
    ('POSTGRESQL', 'public', 'store', 'TABELA', 'Loja (filial) de uma empresa. Cada loja é também um perfil STORE.'),
    ('POSTGRESQL', 'bi', 'dim_alimento', 'VIEW', 'Dimensão alimento (food) com a categoria desnormalizada.'),
    ('POSTGRESQL', 'bi', 'dim_empresa', 'VIEW', 'Dimensão empresa com o plano desnormalizado.'),
    ('POSTGRESQL', 'bi', 'dim_localidade', 'VIEW', 'Dimensão localidade (address) sem rua, número nem CEP. sk_localidade = -1 é "não informado".'),
    ('POSTGRESQL', 'bi', 'dim_perfil', 'VIEW', 'Dimensão perfil sem nome, e-mail ou telefone.'),
    ('POSTGRESQL', 'bi', 'dim_tempo', 'VIEW', 'Dimensão calendário (1 linha por dia) do primeiro cadastro até 1 ano à frente. sk_data = -1 é "não informado".'),
    ('POSTGRESQL', 'bi', 'fato_cadastro', 'VIEW', 'Fato cadastro. Grão: 1 perfil.'),
    ('POSTGRESQL', 'bi', 'fato_estoque', 'VIEW', 'Fato estoque. Grão: 1 item hoje na despensa.'),
    ('POSTGRESQL', 'bi', 'fato_estoque_minimo', 'VIEW', 'Fato estoque mínimo. Grão: household x alimento com mínimo > 0.'),
    ('POSTGRESQL', 'bi', 'fato_movimento', 'VIEW', 'Fato movimento. Grão: 1 item consumido ou descartado (bi_hist.registro_estoque).'),
    ('POSTGRESQL', 'bi', 'fato_pagamento', 'VIEW', 'Fato pagamento. Grão: 1 cobrança mensal.'),
    ('POSTGRESQL', 'bi', 'kpi_d1_desperdicio_mensal', 'VIEW', 'D1: taxa de desperdício = expirados / (expirados + consumidos), por mês e região.'),
    ('POSTGRESQL', 'bi', 'kpi_d3_d4_d8_validade_uf', 'VIEW', 'D3 (% vencidos), D4 (% a vencer em 7 dias) e D8 (% sem validade) dos itens na despensa, por UF.'),
    ('POSTGRESQL', 'bi', 'kpi_d5_ranking_vencimento_uf', 'VIEW', 'D5: ranking de UFs por itens vencidos ou a vencer em 30 dias.'),
    ('POSTGRESQL', 'bi', 'kpi_d6_estoque_minimo_uf', 'VIEW', 'D6: % de households com algum alimento abaixo do mínimo, por UF.'),
    ('POSTGRESQL', 'bi', 'kpi_d7_vida_util_categoria', 'VIEW', 'D7: vida útil no cadastro (validade - entrada), por categoria.'),
    ('POSTGRESQL', 'bi', 'kpi_d9_desperdicio_categoria', 'VIEW', 'D9: itens expirados da categoria / households que têm a categoria.'),
    ('POSTGRESQL', 'bi', 'vw_kpi_cards', 'VIEW', 'Cards do dashboard: valor, meta, desvio e situação de D1-D9, financeiro (F1, F2) e base ativa (U1).'),
    ('POSTGRESQL', 'bi', 'vw_volume_tabelas', 'VIEW', 'Teste de volume: registros por tabela e se atinge 500.'),
    ('POSTGRESQL', 'bi_hist', 'registro_estoque', 'TABELA', 'Histórico de saída da despensa: 1 linha por item consumido ou descartado vencido.'),
    ('POSTGRESQL', 'bi', 'kpi_d1_evolucao_mensal', 'VIEW', 'D1 por mês com running total da perda, variação mês a mês, média móvel de 3 meses e ranking (window functions).'),
    ('POSTGRESQL', 'auditoria', 'log_alteracao', 'TABELA', 'Tabela pai dos logs de auditoria (herança). Consultá-la retorna os logs de todas as filhas (V9).'),
    ('POSTGRESQL', 'auditoria', 'log_profile', 'TABELA', 'Log de INSERT/UPDATE/DELETE em profile; herda as colunas de log_alteracao (V9).'),
    ('POSTGRESQL', 'auditoria', 'log_payment', 'TABELA', 'Log de INSERT/UPDATE/DELETE em payment; herda as colunas de log_alteracao (V9).');

-- ------------------------------------------------------------------ colunas
-- public.address
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''address_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do endereço (serial).'),
    ('neighborhood', 2, 'character varying(100)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Bairro.'),
    ('street', 3, 'character varying(150)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Logradouro.'),
    ('number', 4, 'character varying(10)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Número do imóvel (texto: aceita S/N, 12A).'),
    ('cep', 5, 'character(8)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'CEP com 8 dígitos, sem máscara.'),
    ('city', 6, 'character varying(100)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Cidade.'),
    ('state', 7, 'character(2)', FALSE, NULL, NULL, NULL, 'INTERNO', 'UF com 2 letras maiúsculas. Ex.: SP.'),
    ('latitude', 8, 'numeric(9,6)', TRUE, NULL, NULL, NULL, 'PESSOAL', 'Latitude em graus decimais (V4).'),
    ('longitude', 9, 'numeric(9,6)', TRUE, NULL, NULL, NULL, 'PESSOAL', 'Longitude em graus decimais (V4).')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'address';

-- public.auth_method
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''auth_method_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do método de login (serial).'),
    ('profile_id', 2, 'integer', FALSE, NULL, 'FK, UK', 'profile.id', 'INTERNO', 'Perfil que usa este login (FK profile.id, cascata).'),
    ('provider', 3, 'auth_provider_enum', FALSE, NULL, 'UK', NULL, 'INTERNO', 'Provedor (auth_provider_enum).'),
    ('credential', 4, 'character varying(255)', FALSE, NULL, NULL, NULL, 'SIGILOSO', 'Subject do Google ou hash da senha. Nunca expor.'),
    ('created_at', 5, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Quando o método foi vinculado ao perfil.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'auth_method';

-- public.category
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''category_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da categoria (serial).'),
    ('category_name', 2, 'character varying(100)', FALSE, NULL, 'UK', NULL, 'INTERNO', 'Nome da categoria, único. Ex.: Laticínios e Ovos.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'category';

-- public.company
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''company_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da empresa (serial).'),
    ('plan_id', 2, 'integer', FALSE, NULL, 'FK', 'plan.id', 'INTERNO', 'Plano atual da empresa (FK plan.id).'),
    ('cnpj', 3, 'character(14)', FALSE, NULL, 'UK', NULL, 'INTERNO', 'CNPJ com 14 dígitos, sem máscara, único.'),
    ('profile_id', 4, 'integer', FALSE, NULL, 'FK, UK', 'profile.id', 'INTERNO', 'Perfil COMPANY da empresa (FK profile.id, 1:1).')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'company';

-- public.daily_active_users
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('activity_date', 1, 'date', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Dia da atividade no fuso America/Sao_Paulo. PK composta (activity_date, user_id).'),
    ('user_id', 2, 'integer', FALSE, NULL, 'PK, FK', 'profile.id', 'INTERNO', 'Usuário ativo no dia (FK profile.id, cascata).'),
    ('first_seen_at', 3, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Momento do primeiro acesso/login do usuário no dia.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'daily_active_users';

-- public.vw_dau
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('activity_date', 1, 'date', TRUE, NULL, NULL, NULL, 'INTERNO', 'Dia (fuso America/Sao_Paulo).'),
    ('dau', 2, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Quantidade de usuários distintos ativos no dia.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'vw_dau';

-- public.food
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''food_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do alimento (serial).'),
    ('name', 2, 'character varying(150)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome do produto. Ex.: Arroz branco tipo 1.'),
    ('category_id', 3, 'integer', FALSE, NULL, 'FK', 'category.id', 'INTERNO', 'Categoria do alimento (FK category.id).'),
    ('product_brand', 4, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Marca do produto; nulo para itens a granel.'),
    ('package_quantity', 5, 'numeric(10,2)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade da embalagem, na unidade de unit_of_measure. Maior que zero.'),
    ('unit_of_measure', 6, 'unit_of_measure_enum', FALSE, NULL, NULL, NULL, 'INTERNO', 'Unidade de package_quantity (unit_of_measure_enum).'),
    ('gtin', 7, 'character varying(14)', TRUE, NULL, 'UK', NULL, 'INTERNO', 'Código de barras GTIN/EAN (até 14 dígitos), único. Identificador natural do produto desde a V6.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'food';

-- public.pantry_item
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''pantry_item_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do item (serial).'),
    ('food_id', 2, 'integer', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (FK food.id).'),
    ('profile_id', 3, 'integer', FALSE, NULL, 'FK', 'profile.id', 'INTERNO', 'Household dono do item (FK profile.id, cascata).'),
    ('quantity', 4, 'integer', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade de embalagens. Maior que zero.'),
    ('expiry_date', 5, 'date', TRUE, NULL, NULL, NULL, 'INTERNO', 'Data de validade; nulo quando o produto não tem validade impressa (granel, feira).'),
    ('created_at', 6, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Quando o item entrou na despensa (compra).')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'pantry_item';

-- public.pantry_product_setting
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''pantry_product_setting_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da configuração (serial).'),
    ('food_id', 2, 'integer', FALSE, NULL, 'FK, UK', 'food.id', 'INTERNO', 'Alimento monitorado (FK food.id, cascata).'),
    ('profile_id', 3, 'integer', FALSE, NULL, 'FK, UK', 'profile.id', 'INTERNO', 'Household (FK profile.id, cascata). Único por household e alimento.'),
    ('minimum_quantity', 4, 'integer', FALSE, '0', NULL, NULL, 'INTERNO', 'Quantidade mínima de embalagens; 0 desliga o alerta.'),
    ('created_at', 5, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data de criação da configuração.'),
    ('updated_at', 6, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data da última alteração do mínimo.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'pantry_product_setting';

-- public.payment
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''payment_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da cobrança (serial).'),
    ('due_date', 2, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Data de vencimento.'),
    ('billing_period_start', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início do período cobrado (competência).'),
    ('billing_period_end', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Fim do período cobrado; maior ou igual ao início.'),
    ('payment_status', 5, 'payment_status_enum', FALSE, NULL, NULL, NULL, 'INTERNO', 'Situação da cobrança (payment_status_enum).'),
    ('company_id', 6, 'integer', FALSE, NULL, 'FK', 'company.id', 'INTERNO', 'Empresa cobrada (FK company.id).'),
    ('plan_id', 7, 'integer', FALSE, NULL, 'FK', 'plan.id', 'INTERNO', 'Plano vigente no período cobrado (FK plan.id); pode diferir do plano atual da empresa.'),
    ('amount', 8, 'numeric(10,2)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Valor cobrado em R$.'),
    ('created_at', 9, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data de emissão da cobrança.'),
    ('updated_at', 10, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data da última mudança de situação.'),
    ('paid_at', 11, 'timestamp without time zone', TRUE, NULL, NULL, NULL, 'INTERNO', 'Data e hora do pagamento; nulo enquanto não pago.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'payment';

-- public.plan
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''plan_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do plano (serial).'),
    ('plan_price', 2, 'numeric(10,2)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Mensalidade em R$.'),
    ('plan_name', 3, 'character varying(80)', FALSE, NULL, 'UK', NULL, 'INTERNO', 'Nome comercial do plano, único.'),
    ('store_limit', 4, 'integer', FALSE, NULL, NULL, NULL, 'INTERNO', 'Máximo de lojas que a empresa pode cadastrar no plano.'),
    ('description', 5, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Recursos incluídos no plano.'),
    ('is_active', 6, 'boolean', FALSE, 'true', NULL, NULL, 'INTERNO', 'Plano disponível para venda.'),
    ('created_at', 7, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data de criação do registro.'),
    ('updated_at', 8, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data da última alteração do registro.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'plan';

-- public.profile
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''profile_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do perfil (serial). Referenciado também pelo MongoDB (household_id, account_id, profile_id).'),
    ('address_id', 2, 'integer', TRUE, NULL, 'FK', 'address.id', 'INTERNO', 'Endereço do perfil (FK address.id). Obrigatório para HOUSEHOLD e STORE (V7); opcional para ADMIN e COMPANY.'),
    ('email', 3, 'character varying(255)', FALSE, NULL, 'UK', NULL, 'PESSOAL', 'E-mail de login, único.'),
    ('name', 4, 'character varying(150)', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Nome da pessoa (HOUSEHOLD/ADMIN) ou razão social (COMPANY/STORE).'),
    ('created_at', 5, 'timestamp without time zone', FALSE, 'CURRENT_TIMESTAMP', NULL, NULL, 'INTERNO', 'Data e hora do cadastro.'),
    ('type', 6, 'profile_type_enum', FALSE, NULL, NULL, NULL, 'INTERNO', 'Tipo do perfil (profile_type_enum). Imutável.'),
    ('profile_image_url', 7, 'character varying(500)', TRUE, NULL, NULL, NULL, 'PESSOAL', 'URL da foto de perfil.'),
    ('status', 8, 'profile_status_enum', FALSE, '''ACTIVE''::profile_status_enum', NULL, NULL, 'INTERNO', 'Situação do perfil (profile_status_enum). Padrão ACTIVE.'),
    ('dietary_restrictions', 9, 'text[]', FALSE, '''{}''::text[]', NULL, NULL, 'SENSIVEL', 'Lista de códigos de restrição alimentar do household (alergias, intolerâncias, dietas, condições de saúde ou religiosas), V8. O catálogo de códigos fica no frontend. Lista vazia = nenhuma.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'profile';

-- public.profile_phone
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('profile_id', 1, 'integer', FALSE, NULL, 'PK, FK', 'profile.id', 'INTERNO', 'Perfil dono do telefone (FK profile.id, cascata).'),
    ('phone', 2, 'character varying(16)', FALSE, NULL, 'PK', NULL, 'PESSOAL', 'Telefone no formato E.164: +, DDI e número, 8 a 15 dígitos.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'profile_phone';

-- public.store
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''store_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador da loja (serial).'),
    ('cnpj', 2, 'character(14)', FALSE, NULL, 'UK', NULL, 'INTERNO', 'CNPJ da filial com 14 dígitos, sem máscara, único.'),
    ('company_id', 3, 'integer', FALSE, NULL, 'FK', 'company.id', 'INTERNO', 'Empresa dona da loja (FK company.id, cascata).'),
    ('profile_id', 4, 'integer', FALSE, NULL, 'FK, UK', 'profile.id', 'INTERNO', 'Perfil STORE da loja (FK profile.id, 1:1).'),
    ('opening_time', 5, 'time without time zone', TRUE, NULL, NULL, NULL, 'INTERNO', 'Horário de abertura, igual para todos os dias (V8). Nulo junto com closing_time.'),
    ('closing_time', 6, 'time without time zone', TRUE, NULL, NULL, NULL, 'INTERNO', 'Horário de fechamento, posterior à abertura (V8). Nulo junto com opening_time.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'public' AND o.objeto_nome = 'store';

-- bi.dim_alimento
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('sk_alimento', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave do alimento (= food.id).'),
    ('alimento', 2, 'character varying(150)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Nome do produto.'),
    ('marca', 3, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Marca.'),
    ('embalagem', 4, 'numeric(10,2)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Quantidade da embalagem.'),
    ('unidade', 5, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Unidade da embalagem.'),
    ('descricao', 6, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Produto + marca + embalagem, para exibição.'),
    ('categoria', 7, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Categoria do alimento.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'dim_alimento';

-- bi.dim_empresa
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('sk_empresa', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave da empresa (= company.id).'),
    ('plano', 2, 'character varying(80)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Plano atual.'),
    ('preco_plano', 3, 'numeric(10,2)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mensalidade do plano em R$.'),
    ('limite_lojas', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Limite de lojas do plano.'),
    ('qtd_lojas', 5, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Lojas cadastradas.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'dim_empresa';

-- bi.dim_localidade
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('sk_localidade', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave da localidade (= address.id).'),
    ('cidade', 2, 'character varying', TRUE, NULL, NULL, NULL, 'INTERNO', 'Cidade.'),
    ('uf', 3, 'bpchar', TRUE, NULL, NULL, NULL, 'INTERNO', 'UF.'),
    ('regiao', 4, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região do IBGE derivada da UF.'),
    ('latitude', 5, 'numeric', TRUE, NULL, NULL, NULL, 'PESSOAL', 'Latitude, para mapas.'),
    ('longitude', 6, 'numeric', TRUE, NULL, NULL, NULL, 'PESSOAL', 'Longitude, para mapas.'),
    ('geo_valida', 7, 'boolean', TRUE, NULL, NULL, NULL, 'INTERNO', 'Coordenada dentro do território brasileiro.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'dim_localidade';

-- bi.dim_perfil
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('sk_perfil', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave do perfil (= profile.id).'),
    ('tipo', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Tipo do perfil.'),
    ('status', 3, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Situação do perfil.'),
    ('login', 4, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Primeiro provedor de login vinculado.'),
    ('ano_mes_cadastro', 5, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mês do cadastro (AAAA-MM).'),
    ('tempo_de_casa', 6, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Faixa de tempo desde o cadastro: 0-3, 3-6 ou 6+ meses.'),
    ('origem', 7, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'APP (dado real) ou SIMULADO_BI (dataload BI, e-mail @bi.nexus.local).')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'dim_perfil';

-- bi.dim_tempo
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('sk_data', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Chave da data no formato AAAAMMDD.'),
    ('data', 2, 'date', TRUE, NULL, NULL, NULL, 'INTERNO', 'Data.'),
    ('ano', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Ano.'),
    ('mes', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mês (1-12).'),
    ('ano_mes', 5, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Ano-mês no formato AAAA-MM.'),
    ('trimestre', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Trimestre (1-4).'),
    ('dia_semana', 7, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Dia da semana ISO (1 = segunda, 7 = domingo).'),
    ('fim_de_semana', 8, 'boolean', TRUE, NULL, NULL, NULL, 'INTERNO', 'Verdadeiro para sábado e domingo.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'dim_tempo';

-- bi.fato_cadastro
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('sk_perfil', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_perfil.'),
    ('sk_localidade', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade.'),
    ('sk_data_cadastro', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: cadastro.'),
    ('qtd', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Sempre 1 (contagem de cadastros).')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'fato_cadastro';

-- bi.fato_estoque
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id_item', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'pantry_item.id (dimensão degenerada).'),
    ('sk_alimento', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_alimento.'),
    ('sk_perfil', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_perfil.'),
    ('sk_localidade', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade.'),
    ('sk_data_entrada', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: entrada na despensa.'),
    ('sk_data_validade', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: validade (-1 sem validade).'),
    ('quantidade', 7, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Embalagens.'),
    ('tem_validade', 8, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se o item tem validade, 0 se não.'),
    ('dias_ate_vencer', 9, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Dias até a validade (negativo = vencido).'),
    ('vida_util_dias', 10, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Validade - data de entrada (D7).'),
    ('status_validade', 11, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'SEM_VALIDADE, VENCIDO, VENCE_7D, VENCE_30D ou OK.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'fato_estoque';

-- bi.fato_estoque_minimo
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('sk_perfil', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_perfil.'),
    ('sk_alimento', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_alimento.'),
    ('sk_localidade', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade.'),
    ('estoque', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Embalagens hoje na despensa.'),
    ('minimo', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mínimo configurado.'),
    ('abaixo_minimo', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se o estoque está abaixo do mínimo.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'fato_estoque_minimo';

-- bi.fato_movimento
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id_movimento', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'registro_estoque.id (dimensão degenerada).'),
    ('sk_alimento', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_alimento.'),
    ('sk_perfil', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_perfil.'),
    ('sk_localidade', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade.'),
    ('sk_data_evento', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: consumo ou descarte.'),
    ('sk_data_compra', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: compra.'),
    ('sk_data_validade', 7, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: validade (-1 sem validade).'),
    ('tipo_evento', 8, 'character varying(30)', TRUE, NULL, NULL, NULL, 'INTERNO', 'item_consumed ou item_expired.'),
    ('expirado', 9, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se foi descartado vencido.'),
    ('consumido', 10, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se foi consumido.'),
    ('qtd_consumida', 11, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Embalagens consumidas.'),
    ('qtd_descartada', 12, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Embalagens descartadas.'),
    ('perda_estimada', 13, 'numeric(10,2)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Perda estimada em R$.'),
    ('dias_em_casa', 14, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Dias entre a compra e o consumo/descarte.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'fato_movimento';

-- bi.fato_pagamento
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id_pagamento', 1, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'payment.id (dimensão degenerada).'),
    ('sk_empresa', 2, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_empresa.'),
    ('sk_localidade', 3, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_localidade (endereço da empresa).'),
    ('sk_data_competencia', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: início do período cobrado.'),
    ('sk_data_pagamento', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'FK dim_tempo: pagamento (-1 não pago).'),
    ('status', 6, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Situação da cobrança.'),
    ('valor', 7, 'numeric(10,2)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Valor em R$.'),
    ('pago_no_prazo', 8, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', '1 se pago até o vencimento.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'fato_pagamento';

-- bi.kpi_d1_desperdicio_mensal
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('ano_mes', 1, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mês do evento (nulo = todos).'),
    ('regiao', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região (nulo = todas).'),
    ('itens_expirados', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens descartados vencidos.'),
    ('itens_consumidos', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens consumidos.'),
    ('taxa_desperdicio_pct', 5, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D1 em %.'),
    ('perda_estimada_rs', 6, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Perda estimada em R$.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'kpi_d1_desperdicio_mensal';

-- bi.kpi_d3_d4_d8_validade_uf
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('uf', 1, 'bpchar', TRUE, NULL, NULL, NULL, 'INTERNO', 'UF (nulo = Brasil).'),
    ('regiao', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região.'),
    ('itens', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens na despensa.'),
    ('itens_com_validade', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens com validade.'),
    ('itens_vencidos', 5, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens vencidos.'),
    ('itens_vencem_7d', 6, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens que vencem em até 7 dias.'),
    ('itens_sem_validade', 7, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens sem validade.'),
    ('d3_vencidos_pct', 8, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D3 em %.'),
    ('d4_vencem_7d_pct', 9, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D4 em %.'),
    ('d8_sem_validade_pct', 10, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D8 em %.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'kpi_d3_d4_d8_validade_uf';

-- bi.kpi_d5_ranking_vencimento_uf
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('uf', 1, 'bpchar', TRUE, NULL, NULL, NULL, 'INTERNO', 'UF.'),
    ('regiao', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região.'),
    ('itens_vencidos', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens vencidos.'),
    ('itens_vencem_30d', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens que vencem em até 30 dias.'),
    ('itens_em_risco', 5, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Vencidos + a vencer em 30 dias.'),
    ('ranking', 6, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'DENSE_RANK por itens em risco (1 = pior).')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'kpi_d5_ranking_vencimento_uf';

-- bi.kpi_d6_estoque_minimo_uf
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('uf', 1, 'bpchar', TRUE, NULL, NULL, NULL, 'INTERNO', 'UF (nulo = Brasil).'),
    ('regiao', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Região.'),
    ('households_com_minimo', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Households com mínimo configurado.'),
    ('households_abaixo', 4, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Households com algum item abaixo do mínimo.'),
    ('d6_abaixo_minimo_pct', 5, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D6 em %.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'kpi_d6_estoque_minimo_uf';

-- bi.kpi_d7_vida_util_categoria
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('categoria', 1, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Categoria (nulo = todas).'),
    ('itens_com_validade', 2, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens com validade.'),
    ('vida_util_media_dias', 3, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Média em dias.'),
    ('vida_util_mediana_dias', 4, 'double precision', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mediana em dias.'),
    ('vida_util_min_dias', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mínimo em dias.'),
    ('vida_util_max_dias', 6, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Máximo em dias.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'kpi_d7_vida_util_categoria';

-- bi.kpi_d9_desperdicio_categoria
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('categoria', 1, 'character varying(100)', TRUE, NULL, NULL, NULL, 'INTERNO', 'Categoria.'),
    ('itens_expirados', 2, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens expirados da categoria.'),
    ('households_com_categoria', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Households que compraram a categoria.'),
    ('d9_indice_desperdicio', 4, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D9: itens expirados por household.'),
    ('ranking', 5, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'DENSE_RANK pelo índice (1 = pior).')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'kpi_d9_desperdicio_categoria';

-- bi.vw_kpi_cards
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('codigo', 1, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Código do KPI (D1..D9, F1, F2, U1).'),
    ('kpi', 2, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Nome do KPI.'),
    ('valor', 3, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Valor atual.'),
    ('unidade', 4, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Unidade do valor.'),
    ('meta', 5, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'Meta (nulo = sem meta).'),
    ('desvio', 6, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Valor - meta.'),
    ('situacao', 7, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'DENTRO_DA_META, FORA_DA_META ou SEM_META.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'vw_kpi_cards';

-- bi.vw_volume_tabelas
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('tabela', 1, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Tabela.'),
    ('registros', 2, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Registros.'),
    ('situacao', 3, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'OK, ABAIXO_DE_500, DOMINIO_FIXO ou LIMITADO_PELOS_PROFILES.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'vw_volume_tabelas';

-- bi_hist.registro_estoque
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'integer', FALSE, 'nextval(''bi_hist.registro_estoque_id_seq''::regclass)', 'PK', NULL, 'INTERNO', 'Identificador do registro (serial).'),
    ('profile_id', 2, 'integer', FALSE, NULL, 'FK', 'profile.id', 'INTERNO', 'Household (FK profile.id, cascata).'),
    ('food_id', 3, 'integer', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (FK food.id).'),
    ('event_type', 4, 'character varying(30)', FALSE, NULL, NULL, NULL, 'INTERNO', 'item_consumed ou item_expired (mesmos valores de records no MongoDB).'),
    ('event_date', 5, 'timestamp without time zone', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quando o item foi consumido ou descartado.'),
    ('purchase_date', 6, 'timestamp without time zone', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quando o item entrou na despensa.'),
    ('expiry_date', 7, 'date', TRUE, NULL, NULL, NULL, 'INTERNO', 'Validade do item; nulo se não tinha validade.'),
    ('consumed_quantity', 8, 'integer', FALSE, '0', NULL, NULL, 'INTERNO', 'Embalagens consumidas (item_consumed).'),
    ('discarded_quantity', 9, 'integer', FALSE, '0', NULL, NULL, 'INTERNO', 'Embalagens descartadas (item_expired).'),
    ('estimated_loss', 10, 'numeric(10,2)', FALSE, '0', NULL, NULL, 'INTERNO', 'Perda estimada em R$ com o descarte.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi_hist' AND o.objeto_nome = 'registro_estoque';

-- bi.kpi_d1_evolucao_mensal
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('ano_mes', 1, 'text', TRUE, NULL, NULL, NULL, 'INTERNO', 'Mês do evento (AAAA-MM).'),
    ('itens_expirados', 2, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens descartados vencidos no mês.'),
    ('itens_movimentados', 3, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Itens consumidos + descartados no mês.'),
    ('taxa_desperdicio_pct', 4, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'D1 do mês, em %.'),
    ('perda_rs', 5, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Perda estimada do mês em R$.'),
    ('perda_acumulada_rs', 6, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Running total da perda: SUM() OVER (ORDER BY ano_mes).'),
    ('variacao_pp', 7, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Variação da taxa em pontos percentuais vs mês anterior (LAG).'),
    ('media_movel_3m', 8, 'numeric', TRUE, NULL, NULL, NULL, 'INTERNO', 'Média móvel da taxa nos últimos 3 meses.'),
    ('ranking_perda', 9, 'bigint', TRUE, NULL, NULL, NULL, 'INTERNO', 'Posição do mês pela perda em R$ (RANK, 1 = maior perda).')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'bi' AND o.objeto_nome = 'kpi_d1_evolucao_mensal';

-- auditoria.log_alteracao, log_profile e log_payment (mesmas colunas, por herança)
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao,
       CASE WHEN v.coluna_nome = 'id' AND o.objeto_nome <> 'log_alteracao' THEN 'PK' END,
       v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('id', 1, 'bigint', FALSE, 'nextval(''auditoria.log_alteracao_id_seq''::regclass)', NULL, NULL, 'INTERNO', 'Identificador do log (sequence compartilhada pela pai e filhas).'),
    ('tabela', 2, 'character varying(63)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Tabela alterada (TG_TABLE_NAME).'),
    ('operacao', 3, 'character varying(6)', FALSE, NULL, NULL, NULL, 'INTERNO', 'INSERT, UPDATE ou DELETE (TG_OP).'),
    ('registro_id', 4, 'integer', TRUE, NULL, NULL, NULL, 'INTERNO', 'id do registro alterado.'),
    ('dados_antigos', 5, 'jsonb', TRUE, NULL, NULL, NULL, 'SENSIVEL', 'Linha antes da alteração (OLD); nulo no INSERT. Pode conter dados pessoais e sensíveis.'),
    ('dados_novos', 6, 'jsonb', TRUE, NULL, NULL, NULL, 'SENSIVEL', 'Linha depois da alteração (NEW); nulo no DELETE. Pode conter dados pessoais e sensíveis.'),
    ('usuario', 7, 'character varying(63)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Usuário do banco que fez a alteração (CURRENT_USER).'),
    ('alterado_em', 8, 'timestamp with time zone', FALSE, 'clock_timestamp()', NULL, NULL, 'INTERNO', 'Momento exato da alteração.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = 'auditoria';

-- ---------------------------------------------------------- regras de negócio
UPDATE catalogo.objeto o SET regra_negocio = r.regra
FROM (VALUES
    ('public', 'profile', 'Tipo imutável (trg_profile_type_lock). HOUSEHOLD e STORE exigem endereço (V7). Status BLOCKED/ACTIVE de empresas e lojas é controlado por sp_update_overdue_payments. Alterações auditadas em auditoria.log_profile.'),
    ('public', 'payment', 'Uma cobrança por empresa e competência (uq_payment_company_period). Geradas por sp_generate_monthly_payments; PENDING vencida vira OVERDUE em sp_update_overdue_payments. Alterações auditadas em auditoria.log_payment.'),
    ('public', 'pantry_item', 'Só para perfis HOUSEHOLD (trg_pantry_household_type). Quantidade > 0. Inserir ou alterar registra o household no DAU (trg_dau_pantry_item). Vencimentos: fn_get_expiring_products.'),
    ('public', 'pantry_product_setting', 'Só para perfis HOUSEHOLD. Um mínimo por household e alimento. Faltas: fn_get_items_below_minimum.'),
    ('public', 'company', 'profile_id deve ser um perfil COMPANY (trg_company_profile_type).'),
    ('public', 'store', 'profile_id deve ser um perfil STORE (trg_store_profile_type). Abertura e fechamento juntos e fechamento > abertura.'),
    ('public', 'auth_method', 'Um método por provedor e perfil; subject do Google único (uq_external_auth_identity).'),
    ('public', 'food', 'GTIN único (V5/V6). Embalagem > 0.'),
    ('public', 'daily_active_users', '1 linha por usuário por dia (PK); repetir o acesso no mesmo dia só mantém o primeiro horário. Cargas em lote com nexus.carga_em_lote = on não contam.'),
    ('auditoria', 'log_alteracao', 'Somente inserção pelos triggers; não alterar nem apagar logs fora da política de retenção.')
) AS r (schema_nome, objeto_nome, regra)
WHERE o.banco = 'POSTGRESQL' AND o.schema_nome = r.schema_nome AND o.objeto_nome = r.objeto_nome;

COMMIT;
