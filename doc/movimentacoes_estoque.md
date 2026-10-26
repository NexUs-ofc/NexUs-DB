O Core grava movimentos reais em bi_hist.registro_estoque ao atender POST /api/stock/{itemId}/movements. O corpo recebe type (CONSUMED ou DISCARDED) e quantity (inteiro positivo). A data é definida pelo servidor.

Cada linha representa uma operação, inclusive saídas parciais do mesmo lote. O Core valida o proprietário e o saldo, bloqueia o lote durante a escrita e grava a baixa e o movimento na mesma transação PostgreSQL.

O histórico se liga somente a pantry_item por pantry_item_id. O perfil, o alimento, a data de entrada e a validade são obtidos pelo lote. Quantidade zero passa a ser válida em pantry_item; o Core preserva esses lotes e os omite do estoque disponível, dos vencidos, das notificações e da varredura de vencimentos. A FK do movimento impede excluir fisicamente lotes com histórico.

Correções de quantidade e remoções manuais não são presumidas como consumo ou descarte. DELETE /api/stock/{id} zera o saldo e preserva o lote; para registrar a causa da saída, use o endpoint de movimentações.

A migration V11 pressupõe que o schema bi_hist e a tabela registro_estoque já existem no contrato antigo. Ela altera essa tabela, sem criar ou recriar o schema ou a tabela. Cada registro existente é vinculado a um lote criado com saldo zero, preservando perfil, alimento, entrada e validade. As quantidades são unificadas e os tipos são convertidos. Registros com quantidades incompatíveis com o tipo interrompem a migration para revisão, sem conversão silenciosa.

A coluna estimated_loss é mantida para preservar valores históricos e aceita ausência de valor. O Core não calcula perdas financeiras porque o preço de compra não faz parte do estoque atual.

A V11 adapta apenas as views necessárias: fato_movimento obtém os dados pelo lote, dim_tempo obtém a validade em pantry_item e fato_estoque exclui saldo zero. A carga simulada também usa o contrato novo. As fórmulas e os critérios dos KPIs não são redesenhados nesta etapa: continuam contando operações, não quantidades. O nome histórico expirado nas views representa DISCARDED, inclusive descartes sem vencimento.

Execute a V11 antes de publicar o Core. Para atualizar o catálogo SQL já instalado, execute script/05_catalogo/02_metadados_postgres.sql e script/05_catalogo/03_metadados_mongodb.sql após a migration.

Em bancos de teste vazios, aplique as migrations até a V10, prepare o estado anterior com tests/fixtures/registro_estoque_pre_v11.sql e depois execute o restante das migrations. Essa preparação é usada pelo CI para reproduzir a estrutura preexistente; não é uma etapa necessária no banco que já possui a tabela.
