"""Regras de transformação: convertem valores do banco legado para o formato do banco novo.

Cada função devolve o valor já normalizado ou levanta ValueError com o motivo,
para que o registro seja rejeitado (e logado) sem interromper a carga.
"""
import re
import unicodedata

UFS = {
    "acre": "AC", "alagoas": "AL", "amapa": "AP", "amazonas": "AM", "bahia": "BA",
    "ceara": "CE", "distrito federal": "DF", "espirito santo": "ES", "goias": "GO",
    "maranhao": "MA", "mato grosso": "MT", "mato grosso do sul": "MS",
    "minas gerais": "MG", "para": "PA", "paraiba": "PB", "parana": "PR",
    "pernambuco": "PE", "piaui": "PI", "rio de janeiro": "RJ",
    "rio grande do norte": "RN", "rio grande do sul": "RS", "rondonia": "RO",
    "roraima": "RR", "santa catarina": "SC", "sao paulo": "SP", "sergipe": "SE",
    "tocantins": "TO",
}


def texto(valor: str | None, campo: str, tamanho: int) -> str:
    valor = (valor or "").strip()
    if not valor:
        raise ValueError(f"{campo} vazio")
    if len(valor) > tamanho:
        raise ValueError(f"{campo} com mais de {tamanho} caracteres")
    return valor


def texto_opcional(valor: str | None, campo: str, tamanho: int) -> str | None:
    return texto(valor, campo, tamanho) if (valor or "").strip() else None


def email(valor: str | None) -> str:
    valor = (valor or "").strip().lower()
    if len(valor) > 255 or not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", valor):
        raise ValueError(f"email inválido: '{valor}'")
    return valor


def cep(valor: str | None) -> str:
    digitos = re.sub(r"\D", "", valor or "")
    if len(digitos) != 8:
        raise ValueError(f"CEP inválido: '{valor}'")
    return digitos


def uf(valor: str | None) -> str:
    valor = (valor or "").strip()
    if re.fullmatch(r"[A-Za-z]{2}", valor):
        return valor.upper()
    sem_acento = unicodedata.normalize("NFKD", valor).encode("ascii", "ignore").decode()
    sigla = UFS.get(sem_acento.lower())
    if sigla is None:
        raise ValueError(f"estado inválido: '{valor}'")
    return sigla


def telefone(valor: str | None) -> str:
    """Converte para E.164 (+5511987654321). Números sem DDI recebem +55."""
    valor = (valor or "").strip()
    digitos = re.sub(r"\D", "", valor)
    if not valor.startswith("+"):
        digitos = digitos.lstrip("0")  # remove prefixo de operadora/longa distância
        if len(digitos) in (10, 11):
            digitos = "55" + digitos
    numero = "+" + digitos
    if not re.fullmatch(r"\+[1-9][0-9]{7,14}", numero):
        raise ValueError(f"telefone inválido: '{valor}'")
    return numero


def gtin(valor: str | None) -> str | None:
    """Código de barras válido como GTIN (8, 12, 13 ou 14 dígitos); senão None."""
    digitos = re.sub(r"[\s-]", "", valor or "")
    return digitos if re.fullmatch(r"\d{8}|\d{12,14}", digitos) else None


def quantidade(valor: int | None) -> int:
    if valor is None or valor <= 0:
        raise ValueError(f"quantidade inválida: {valor}")
    return valor
