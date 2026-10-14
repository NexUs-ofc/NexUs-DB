"""Etapas do RPA: cada uma extrai do banco legado, transforma e carrega no banco novo.

As etapas seguem a ordem das chaves estrangeiras do destino. Cada registro
migrado é gravado em rpa.mapeamento (id legado -> id novo) na mesma transação
da carga, o que torna a execução idempotente: o que já está mapeado é pulado.
"""
import logging
from contextlib import contextmanager
from dataclasses import dataclass

import psycopg2
from psycopg2.extras import RealDictCursor

from . import transformacao as t

log = logging.getLogger("rpa")

# Erros causados pelo conteúdo de um registro: rejeitam só o registro.
# Qualquer outro erro (conexão, permissão, SQL) interrompe a etapa.
ERROS_DE_DADO = (ValueError, psycopg2.IntegrityError, psycopg2.DataError,
                 psycopg2.errors.RaiseException)


@dataclass
class Resumo:
    migrados: int = 0
    ja_migrados: int = 0
    rejeitados: int = 0

    def __str__(self) -> str:
        return (f"{self.migrados} migrados, {self.ja_migrados} já migrados, "
                f"{self.rejeitados} rejeitados")


def extrair(legado, sql: str) -> list[dict]:
    with legado.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql)
        return cur.fetchall()


def mapeados(cur, entidade: str) -> dict[int, int]:
    cur.execute("SELECT id_legado, id_novo FROM rpa.mapeamento WHERE entidade = %s",
                (entidade,))
    return dict(cur.fetchall())


def mapear(cur, entidade: str, id_legado: int, id_novo: int):
    cur.execute("INSERT INTO rpa.mapeamento (entidade, id_legado, id_novo) VALUES (%s, %s, %s)",
                (entidade, id_legado, id_novo))


def _mensagem(erro: Exception) -> str:
    if isinstance(erro, psycopg2.Error) and erro.diag.message_primary:
        detalhe = erro.diag.message_detail
        return erro.diag.message_primary + (f" ({detalhe})" if detalhe else "")
    return str(erro)


@contextmanager
def registro(cur, resumo: Resumo, descricao: str):
    """Isola um registro em um savepoint: se o dado for inválido, desfaz só ele."""
    cur.execute("SAVEPOINT registro")
    try:
        yield
    except ERROS_DE_DADO as erro:
        cur.execute("ROLLBACK TO SAVEPOINT registro")
        resumo.rejeitados += 1
        log.warning("%s rejeitado: %s", descricao, _mensagem(erro))
    else:
        cur.execute("RELEASE SAVEPOINT registro")


def migrar_categorias(legado, cur) -> Resumo:
    resumo, feitos = Resumo(), mapeados(cur, "categoria")
    for linha in extrair(legado, "SELECT id_categoria AS id, nome FROM tb_categoria ORDER BY 1"):
        if linha["id"] in feitos:
            resumo.ja_migrados += 1
            continue
        with registro(cur, resumo, f"tb_categoria id={linha['id']}"):
            # category_name é UNIQUE: se a categoria já existe no destino, reaproveita
            cur.execute(
                """INSERT INTO category (category_name) VALUES (%s)
                   ON CONFLICT (category_name) DO UPDATE SET category_name = EXCLUDED.category_name
                   RETURNING id""",
                (t.texto(linha["nome"], "nome", 100),),
            )
            mapear(cur, "categoria", linha["id"], cur.fetchone()[0])
            resumo.migrados += 1
    return resumo


def migrar_alimentos(legado, cur) -> Resumo:
    resumo, feitos = Resumo(), mapeados(cur, "alimento")
    categorias = mapeados(cur, "categoria")
    sql = ("SELECT id_alimento AS id, codigo_barras, nome, marca, id_categoria "
           "FROM tb_alimento ORDER BY 1")
    for linha in extrair(legado, sql):
        if linha["id"] in feitos:
            resumo.ja_migrados += 1
            continue
        descricao = f"tb_alimento id={linha['id']}"
        with registro(cur, resumo, descricao):
            if linha["id_categoria"] not in categorias:
                raise ValueError(f"categoria {linha['id_categoria']} não migrada")
            nome = t.texto(linha["nome"], "nome", 150)
            marca = t.texto_opcional(linha["marca"], "marca", 100)
            gtin = t.gtin(linha["codigo_barras"])
            if linha["codigo_barras"] and not gtin:
                log.warning("%s: código de barras '%s' não é um GTIN válido; migrado sem GTIN",
                            descricao, linha["codigo_barras"])

            food_id = None
            if gtin:  # gtin é UNIQUE: se o produto já existe no destino, reaproveita
                cur.execute("SELECT id FROM food WHERE gtin = %s", (gtin,))
                existente = cur.fetchone()
                food_id = existente[0] if existente else None
            if food_id is None:
                # o legado não tem embalagem: assume 1 unidade
                cur.execute(
                    """INSERT INTO food (name, category_id, product_brand,
                                         package_quantity, unit_of_measure, gtin)
                       VALUES (%s, %s, %s, 1, 'unit', %s) RETURNING id""",
                    (nome, categorias[linha["id_categoria"]], marca, gtin),
                )
                food_id = cur.fetchone()[0]
            mapear(cur, "alimento", linha["id"], food_id)
            resumo.migrados += 1
    return resumo


def migrar_usuarios(legado, cur) -> Resumo:
    """tb_usuario -> profile HOUSEHOLD, com o endereço da primeira casa do usuário."""
    resumo, feitos = Resumo(), mapeados(cur, "usuario")
    enderecos = mapeados(cur, "endereco")
    sql = """
        SELECT u.id_usuario AS id, u.nome, u.email,
               e.id_endereco, e.rua, e.numero, e.bairro, e.cidade, e.estado, e.cep
          FROM tb_usuario u
          LEFT JOIN LATERAL (SELECT c.id_endereco FROM tb_casa c
                              WHERE c.id_usuario = u.id_usuario
                              ORDER BY c.id_casa LIMIT 1) casa ON TRUE
          LEFT JOIN tb_endereco e ON e.id_endereco = casa.id_endereco
         ORDER BY u.id_usuario
    """
    for linha in extrair(legado, sql):
        if linha["id"] in feitos:
            resumo.ja_migrados += 1
            continue
        with registro(cur, resumo, f"tb_usuario id={linha['id']}"):
            if linha["id_endereco"] is None:
                raise ValueError("usuário sem casa/endereço (obrigatório para HOUSEHOLD)")
            nome = t.texto(linha["nome"], "nome", 150)
            email = t.email(linha["email"])

            address_id = enderecos.get(linha["id_endereco"])
            if address_id is None:
                cur.execute(
                    """INSERT INTO address (street, number, neighborhood, city, state, cep)
                       VALUES (%s, %s, %s, %s, %s, %s) RETURNING id""",
                    (t.texto(linha["rua"], "rua", 150), t.texto(linha["numero"], "numero", 10),
                     t.texto(linha["bairro"], "bairro", 100), t.texto(linha["cidade"], "cidade", 100),
                     t.uf(linha["estado"]), t.cep(linha["cep"])),
                )
                address_id = cur.fetchone()[0]
                mapear(cur, "endereco", linha["id_endereco"], address_id)

            # email é UNIQUE no destino: duplicado é rejeitado com a mensagem do banco
            cur.execute(
                """INSERT INTO profile (address_id, email, name, type)
                   VALUES (%s, %s, %s, 'HOUSEHOLD') RETURNING id""",
                (address_id, email, nome),
            )
            mapear(cur, "usuario", linha["id"], cur.fetchone()[0])
            enderecos[linha["id_endereco"]] = address_id
            resumo.migrados += 1
    return resumo


def migrar_casas(legado, cur) -> Resumo:
    """tb_casa não tem tabela própria: cada casa passa a apontar para o profile do dono."""
    resumo, feitos = Resumo(), mapeados(cur, "casa")
    usuarios = mapeados(cur, "usuario")
    for linha in extrair(legado, "SELECT id_casa AS id, id_usuario FROM tb_casa ORDER BY 1"):
        if linha["id"] in feitos:
            resumo.ja_migrados += 1
            continue
        with registro(cur, resumo, f"tb_casa id={linha['id']}"):
            if linha["id_usuario"] not in usuarios:
                raise ValueError(f"usuário {linha['id_usuario']} não migrado")
            mapear(cur, "casa", linha["id"], usuarios[linha["id_usuario"]])
            resumo.migrados += 1
    return resumo


def migrar_telefones(legado, cur) -> Resumo:
    """Telefones de usuários e de casas -> profile_phone (PK composta garante idempotência)."""
    resumo = Resumo()
    perfis = {"usuario": mapeados(cur, "usuario"), "casa": mapeados(cur, "casa")}
    sql = """
        SELECT 'usuario' AS dono, ut.id_usuario AS id_dono, t.id_telefone, t.numero
          FROM tb_usuario_telefone ut JOIN tb_telefone t USING (id_telefone)
        UNION ALL
        SELECT 'casa', ct.id_casa, t.id_telefone, t.numero
          FROM tb_casa_telefone ct JOIN tb_telefone t USING (id_telefone)
        ORDER BY 1, 2, 3
    """
    for linha in extrair(legado, sql):
        descricao = f"tb_telefone id={linha['id_telefone']} ({linha['dono']} {linha['id_dono']})"
        with registro(cur, resumo, descricao):
            profile_id = perfis[linha["dono"]].get(linha["id_dono"])
            if profile_id is None:
                raise ValueError(f"{linha['dono']} {linha['id_dono']} não migrado")
            cur.execute(
                "INSERT INTO profile_phone (profile_id, phone) VALUES (%s, %s) ON CONFLICT DO NOTHING",
                (profile_id, t.telefone(linha["numero"])),
            )
            if cur.rowcount:
                resumo.migrados += 1
            else:
                resumo.ja_migrados += 1
    return resumo


def migrar_itens_dispensa(legado, cur) -> Resumo:
    resumo, feitos = Resumo(), mapeados(cur, "item_dispensa")
    casas, alimentos = mapeados(cur, "casa"), mapeados(cur, "alimento")
    sql = ("SELECT id_item AS id, id_casa, id_alimento, quantidade, data_validade "
           "FROM tb_item_dispensa ORDER BY 1")
    for linha in extrair(legado, sql):
        if linha["id"] in feitos:
            resumo.ja_migrados += 1
            continue
        with registro(cur, resumo, f"tb_item_dispensa id={linha['id']}"):
            if linha["id_casa"] not in casas:
                raise ValueError(f"casa {linha['id_casa']} não migrada")
            if linha["id_alimento"] not in alimentos:
                raise ValueError(f"alimento {linha['id_alimento']} não migrado")
            cur.execute(
                """INSERT INTO pantry_item (food_id, profile_id, quantity, expiry_date)
                   VALUES (%s, %s, %s, %s) RETURNING id""",
                (alimentos[linha["id_alimento"]], casas[linha["id_casa"]],
                 t.quantidade(linha["quantidade"]), linha["data_validade"]),
            )
            mapear(cur, "item_dispensa", linha["id"], cur.fetchone()[0])
            resumo.migrados += 1
    return resumo


# Ordem de execução (respeita as dependências entre as tabelas de destino)
ETAPAS = [
    ("categorias", migrar_categorias),
    ("alimentos", migrar_alimentos),
    ("usuarios", migrar_usuarios),
    ("casas", migrar_casas),
    ("telefones", migrar_telefones),
    ("itens_dispensa", migrar_itens_dispensa),
]
