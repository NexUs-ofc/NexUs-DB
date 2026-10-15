"""RPA de migração: banco legado -> banco novo normalizado do NexUs.

Uso (a partir da raiz NexUs-DB/):  python -m rpa.src.main
"""
import logging
import os
import sys
from pathlib import Path

import psycopg2

from script.dataload.src.config import get_env  # também carrega o .env

from .etapas import ETAPAS

LOG_ARQUIVO = Path(__file__).resolve().parent.parent / "logs" / "rpa.log"

# Estrutura de controle no banco novo (schema próprio, não altera as tabelas do app)
CONTROLE = """
CREATE SCHEMA IF NOT EXISTS rpa;
CREATE TABLE IF NOT EXISTS rpa.mapeamento (
    entidade   VARCHAR(30) NOT NULL,
    id_legado  INTEGER NOT NULL,
    id_novo    INTEGER NOT NULL,
    migrado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (entidade, id_legado)
);
CREATE TABLE IF NOT EXISTS rpa.execucao (
    id       SERIAL PRIMARY KEY,
    inicio   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    fim      TIMESTAMP,
    status   VARCHAR(10) NOT NULL DEFAULT 'EXECUTANDO'
             CHECK (status IN ('EXECUTANDO', 'SUCESSO', 'FALHA')),
    etapa    VARCHAR(30),
    mensagem TEXT,
    resumo   TEXT
);
"""

log = logging.getLogger("rpa")


def configurar_log():
    LOG_ARQUIVO.parent.mkdir(exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[logging.StreamHandler(), logging.FileHandler(LOG_ARQUIVO, encoding="utf-8")],
    )


def conectar(prefixo: str):
    conn = psycopg2.connect(
        host=get_env(f"{prefixo}_HOST"),
        port=get_env(f"{prefixo}_PORT"),
        dbname=get_env(f"{prefixo}_DATABASE"),
        user=get_env(f"{prefixo}_USER"),
        password=get_env(f"{prefixo}_PASSWORD"),
        sslmode=os.getenv(f"{prefixo}_SSLMODE"),  # opcional; None usa o padrão/PGSSLMODE
    )
    conn.autocommit = False
    return conn


def finalizar(destino, execucao_id, status: str, etapa, mensagem, resumo: list[str]):
    """Grava o resultado em rpa.execucao (em transação própria, após o rollback)."""
    if destino is None or execucao_id is None:
        return
    try:
        with destino.cursor() as cur:
            cur.execute(
                """UPDATE rpa.execucao SET fim = CURRENT_TIMESTAMP, status = %s,
                          etapa = %s, mensagem = %s, resumo = %s
                    WHERE id = %s""",
                (status, etapa, mensagem, "\n".join(resumo), execucao_id),
            )
        destino.commit()
    except psycopg2.Error as erro:
        log.error("Não foi possível registrar o resultado da execução %s: %s", execucao_id, erro)


def main() -> int:
    configurar_log()
    legado = destino = execucao_id = None
    etapa, resumo = "conexao", []
    try:
        destino = conectar("PG")
        legado = conectar("LEGADO_PG")
        # o legado só é lido: um snapshot único garante leitura consistente entre as etapas
        legado.set_session(readonly=True, isolation_level="REPEATABLE READ")

        etapa = "preparacao"
        with destino.cursor() as cur:
            cur.execute(CONTROLE)
            cur.execute("INSERT INTO rpa.execucao DEFAULT VALUES RETURNING id")
            execucao_id = cur.fetchone()[0]
        destino.commit()
        log.info("Execução %s iniciada", execucao_id)

        for etapa, migrar in ETAPAS:
            log.info("[%s] iniciando", etapa)
            with destino.cursor() as cur:
                resultado = migrar(legado, cur)
            destino.commit()  # cada etapa é uma transação: dados + mapeamento juntos
            resumo.append(f"{etapa}: {resultado}")
            log.info("[%s] concluída: %s", etapa, resultado)

        finalizar(destino, execucao_id, "SUCESSO", None, None, resumo)
        log.info("Execução %s concluída com sucesso", execucao_id)
        return 0
    except Exception as erro:
        log.exception("Falha na etapa '%s'", etapa)
        if destino is not None and not destino.closed:
            try:
                destino.rollback()  # desfaz só a etapa em andamento; as anteriores ficam gravadas
            except psycopg2.Error:
                pass  # conexão perdida: o PostgreSQL já descarta a transação aberta
        finalizar(destino, execucao_id, "FALHA", etapa, str(erro), resumo)
        log.error("Corrija a causa e execute novamente: o que já foi migrado será pulado.")
        return 1
    finally:
        for conn in (legado, destino):
            if conn is not None:
                conn.close()


if __name__ == "__main__":
    sys.exit(main())
