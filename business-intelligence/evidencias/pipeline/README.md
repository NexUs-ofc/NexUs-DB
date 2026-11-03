# Evidências — Pipeline

`kpi-conferencia.png` — resultado gerado pelo pipeline: `SELECT * FROM workspace.gold.kpi_conferencia`
no SQL Editor. A Gold recalcula os 8 KPIs com a mesma regra da view do banco (por lote/operação) e
compara com o gabarito `bi.vw_kpi_cards`: em 02/11/2026, os 8 KPIs batem (diferença 0,00, resultado OK).

Os cards do dashboard usam a regra oficial por unidade, por isso alguns valores diferem desta tabela.
