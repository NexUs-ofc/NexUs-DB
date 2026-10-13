-- =============================================================================
-- NexUs — Catálogo de metadados (3/3): collections do MongoDB
-- O MongoDB não guarda schema; fonte: script/dataload/src/factories/home.py.
-- Referências a profile.id, food.id etc. são lógicas: o MongoDB não aplica FK.
-- Mudou uma collection? Edite este arquivo e rode só ele.
-- Pode rodar de novo quando quiser: apaga e recarrega só os metadados do MongoDB.
-- Requer 01_estrutura.sql já executado.
-- =============================================================================
BEGIN;

DELETE FROM catalogo.objeto WHERE banco = 'MONGODB';  -- as colunas saem em cascata

-- ------------------------------------------------------------------ objetos
INSERT INTO catalogo.objeto (banco, schema_nome, objeto_nome, tipo_objeto, descricao) VALUES
    ('MONGODB', NULL, 'recipes', 'COLLECTION', 'Receitas geradas pela IA ou cadastradas pelo usuário.'),
    ('MONGODB', NULL, 'recipe_accounts', 'COLLECTION', 'Receitas salvas por household (relação N:N receita × perfil).'),
    ('MONGODB', NULL, 'events', 'COLLECTION', 'Eventos planejados pelo household (churrasco, aniversário) com as receitas e o cálculo de ingredientes.'),
    ('MONGODB', NULL, 'shopping_lists', 'COLLECTION', 'Listas de compras, avulsas ou geradas a partir de um evento.'),
    ('MONGODB', NULL, 'records', 'COLLECTION', 'Movimentos de estoque do household. item_consumed e item_expired são os mesmos eventos que o BI lê de bi_hist.registro_estoque (KPIs D1 e D9).'),
    ('MONGODB', NULL, 'notifications', 'COLLECTION', 'Alertas do NexUs-Notify. Formato igual ao domínio Notification do serviço.'),
    ('MONGODB', NULL, 'conversations', 'COLLECTION', 'Histórico das conversas com o assistente.'),
    ('MONGODB', NULL, 'knowledge', 'COLLECTION', 'Fatos que a IA aprendeu sobre o household (gostos, acertos e erros de estimativa).'),
    ('MONGODB', NULL, 'metrics', 'COLLECTION', 'Telemetria da IA: 1 requisição ao assistente.'),
    ('MONGODB', NULL, 'tool_metrics', 'COLLECTION', 'Telemetria da IA: 1 chamada de ferramenta do assistente.'),
    ('MONGODB', NULL, 'traces', 'COLLECTION', 'Telemetria da IA: 1 etapa (span) de execução.');

-- ------------------------------------------------------------------ colunas
-- mongodb.recipes
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador da receita.'),
    ('title', 2, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome da receita.'),
    ('serving_size', 3, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Porções que a receita rende.'),
    ('ingredients', 4, 'array<object>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ingredientes (3 a 8).'),
    ('ingredients.food_id', 5, 'int', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (food.id).'),
    ('ingredients.required_quantity', 6, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade com unidade. Ex.: 500g, 2kg.'),
    ('ingredients.mandatory', 7, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ingrediente indispensável.'),
    ('ingredients.possible_substitutes', 8, 'array<int>', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'food.id que podem substituir (0 a 2).'),
    ('instructions', 9, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Modo de preparo.'),
    ('is_liked', 10, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'Usuário marcou como favorita.'),
    ('created_by', 11, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'ai ou user.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'recipes';

-- mongodb.recipe_accounts
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    ('id_recipe', 2, 'ObjectId', FALSE, NULL, 'FK', 'recipes._id', 'INTERNO', 'Receita (recipes._id).'),
    ('id_account', 3, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    ('created_at', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quando a receita foi salva.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'recipe_accounts';

-- mongodb.events
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador do evento.'),
    ('household_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household dono (profile.id).'),
    ('title', 3, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Título.'),
    ('description', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Descrição livre (pode citar restrições dos convidados).'),
    ('date', 5, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Data e hora do evento.'),
    ('duration', 6, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Duração em minutos.'),
    ('local', 7, 'string', FALSE, NULL, NULL, NULL, 'PESSOAL', 'Local (cidade/endereço livre).'),
    ('qtd_people', 8, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Número de convidados.'),
    ('recipes', 9, 'array<object>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Receitas do evento (1 a 3).'),
    ('recipes.recipe_id', 10, 'ObjectId', FALSE, NULL, 'FK', 'recipes._id', 'INTERNO', 'Receita (recipes._id).'),
    ('recipes.title', 11, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome da receita no evento.'),
    ('recipes.ingredients', 12, 'array<object>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ingredientes calculados para o número de pessoas.'),
    ('recipes.ingredients.food_id', 13, 'int', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (food.id).'),
    ('recipes.ingredients.ingredient', 14, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome do ingrediente.'),
    ('recipes.ingredients.total_quantity', 15, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade total com unidade.'),
    ('recipes.ingredients.has_enough', 16, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'Despensa tem o suficiente.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'events';

-- mongodb.shopping_lists
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    ('household_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    ('event_id', 3, 'ObjectId', TRUE, NULL, 'FK', 'events._id', 'INTERNO', 'Evento de origem (events._id).'),
    ('title', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Título da lista.'),
    ('items', 5, 'array<object>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Itens (2 a 6).'),
    ('items.food_id', 6, 'int', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (food.id).'),
    ('items.ingredient', 7, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Nome do item.'),
    ('items.quantity', 8, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quantidade com unidade.'),
    ('items.purchased', 9, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'Item já comprado.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'shopping_lists';

-- mongodb.records
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    ('account_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    ('date', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Quando o evento aconteceu.'),
    ('event_type', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'item_consumed, item_expired, recipe_status_changed ou shopping_list_added.'),
    ('details', 5, 'object', FALSE, NULL, NULL, NULL, 'INTERNO', 'Detalhes do evento.'),
    ('details.food_id', 6, 'int', FALSE, NULL, 'FK', 'food.id', 'INTERNO', 'Alimento (food.id).'),
    ('details.discarded_quantity', 7, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Embalagens descartadas.'),
    ('details.estimated_loss', 8, 'double', FALSE, NULL, NULL, NULL, 'INTERNO', 'Perda estimada em R$.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'records';

-- mongodb.notifications
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    ('profile_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Destinatário (profile.id).'),
    ('type', 3, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'PRODUCT_EXPIRING ou UPCOMING_EVENT.'),
    ('source_id', 4, 'string', FALSE, NULL, 'FK', 'pantry_item.id ou events._id', 'INTERNO', 'pantry_item.id ou events._id em texto.'),
    ('alert_key', 5, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Evita alerta repetido para o mesmo perfil, tipo e origem.'),
    ('title', 6, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Título.'),
    ('message', 7, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Mensagem.'),
    ('created_at', 8, 'date (UTC)', FALSE, NULL, NULL, NULL, 'INTERNO', 'Envio.'),
    ('read_at', 9, 'date (UTC) ou null', TRUE, NULL, NULL, NULL, 'INTERNO', 'Primeira leitura; null = não lida.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'notifications';

-- mongodb.conversations
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    ('account_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    ('historico', 3, 'array<object>', FALSE, NULL, NULL, NULL, 'SENSIVEL', 'Mensagens; texto livre pode conter dado de saúde.'),
    ('historico.role', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'user ou assistant.'),
    ('historico.content', 5, 'string', FALSE, NULL, NULL, NULL, 'SENSIVEL', 'Texto da mensagem.'),
    ('created_at', 6, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início da conversa.'),
    ('updated_at', 7, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Última mensagem.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'conversations';

-- mongodb.knowledge
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('_id', 1, 'ObjectId', FALSE, NULL, 'PK', NULL, 'INTERNO', 'Identificador.'),
    ('household_id', 2, 'int', FALSE, NULL, 'FK', 'profile.id', 'PESSOAL', 'Household (profile.id).'),
    ('source_agent', 3, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'chat, recipes, events ou stock.'),
    ('knowledge_type', 4, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'preference, recipe_feedback, event_estimation_error ou event_estimation_success.'),
    ('fact', 5, 'string', FALSE, NULL, NULL, NULL, 'SENSIVEL', 'Fato aprendido, em texto livre.'),
    ('context.origin_event_id', 6, 'ObjectId', TRUE, NULL, 'FK', 'events._id', 'INTERNO', 'Evento que originou o fato (events._id).'),
    ('ai_guideline.identified_triggers', 7, 'array<string>', FALSE, NULL, NULL, NULL, 'INTERNO', 'Gatilhos identificados.'),
    ('ai_guideline.recommended_action', 8, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ação recomendada à IA.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'knowledge';

-- mongodb.metrics
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('trace_id', 1, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Identificador da requisição (8 caracteres).'),
    ('route', 2, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Rota do agente: eventos, receitas, estoque ou conversa.'),
    ('started_at', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início.'),
    ('finished_at', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Fim.'),
    ('duration_ms', 5, 'double', FALSE, NULL, NULL, NULL, 'INTERNO', 'Duração em ms.'),
    ('tool_calls', 6, 'int', FALSE, NULL, NULL, NULL, 'INTERNO', 'Ferramentas chamadas.'),
    ('error', 7, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'A requisição falhou.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'metrics';

-- mongodb.tool_metrics
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('trace_id', 1, 'string', FALSE, NULL, 'FK', 'metrics.trace_id', 'INTERNO', 'Requisição (metrics.trace_id).'),
    ('tool_name', 2, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'get_stock, get_recipe, get_event ou create_shopping_list.'),
    ('started_at', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início.'),
    ('finished_at', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Fim.'),
    ('duration_ms', 5, 'double', FALSE, NULL, NULL, NULL, 'INTERNO', 'Duração em ms.'),
    ('success', 6, 'bool', FALSE, NULL, NULL, NULL, 'INTERNO', 'A chamada deu certo.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'tool_metrics';

-- mongodb.traces
INSERT INTO catalogo.coluna (objeto_id, coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
SELECT o.id, v.coluna_nome, v.posicao, v.tipo_dado, v.aceita_nulo, v.valor_padrao, v.chave, v.referencia, v.classificacao_lgpd, v.descricao
FROM catalogo.objeto o
CROSS JOIN (VALUES
    ('trace_id', 1, 'string', FALSE, NULL, 'FK', 'metrics.trace_id', 'INTERNO', 'Requisição (metrics.trace_id).'),
    ('span_name', 2, 'string', FALSE, NULL, NULL, NULL, 'INTERNO', 'Etapa: roteador, banco, ia ou integracao.'),
    ('started_at', 3, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Início.'),
    ('finished_at', 4, 'date', FALSE, NULL, NULL, NULL, 'INTERNO', 'Fim.'),
    ('duration_ms', 5, 'double', FALSE, NULL, NULL, NULL, 'INTERNO', 'Duração em ms.'),
    ('extra', 6, 'object', FALSE, NULL, NULL, NULL, 'INTERNO', 'Atributos adicionais do span.')
) AS v (coluna_nome, posicao, tipo_dado, aceita_nulo, valor_padrao, chave, referencia, classificacao_lgpd, descricao)
WHERE o.banco = 'MONGODB' AND o.objeto_nome = 'traces';

COMMIT;
