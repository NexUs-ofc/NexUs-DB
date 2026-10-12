"""Dataload perfil BI: acrescenta ~12 meses de uso simulado no MESMO banco do app.

Somente PostgreSQL (não grava nada no MongoDB).

Objetivo: carga de volume verossímil, ~500 registros por tabela (ALVO), com variação
suficiente para os KPIs de desperdício D1..D9 do star schema.

- Catálogo com ~550 SKUs de supermercado (produto x marca x embalagem, EAN-13 válido).
- 520 perfis (households, empresas e lojas) espalhados por 60 cidades das 27 UFs.
- Cada item comprado é consumido, vence e é descartado, ou continua na despensa hoje.
  O histórico de consumo/descarte vai para bi_hist.registro_estoque, com os mesmos
  event_type do app (item_consumed / item_expired).
- A simulação gera mais eventos do que o ALVO; pantry_item, pantry_product_setting e o
  histórico são reduzidos por amostra aleatória, o que preserva as proporções dos KPIs.

Não apaga dados do app. Cada execução remove só os próprios dados da execução anterior
(perfis com e-mail @bi.nexus.local, em cascata) e insere de novo. IDs vêm das sequences
do banco, sem conflito com o app.
"""

import os
import random
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from faker import Faker
from psycopg2.extras import execute_values

from .seed import CATEGORIES, PLANS

DOMINIO = "@bi.nexus.local"
JANELA = 365
ALVO = 520  # registros por tabela gerada (pantry_item, settings, histórico, perfis/endereços)
# perfis = endereços = 520. Cada empresa e cada loja também é um perfil, por isso não dá para
# ter 500 empresas e 500 lojas sem passar de 1.000 perfis.
VOL = {"household": 380, "company": 55, "store": 85}
GTIN_PREFIXO = "78991"  # EAN-13 com prefixo Brasil (789); identifica o catálogo do dataload BI

# ------------------------------------------------------------------ catálogo
# produto, categoria, unidade, embalagens, vida útil mín/máx (dias), preço por kg/l/unidade
PRODUTOS = [
    ("Arroz branco tipo 1", "Cereais e Grãos", "kg", [1, 2, 5], 240, 400, 6.2),
    ("Arroz integral", "Cereais e Grãos", "kg", [1, 2], 180, 300, 8.9),
    ("Feijão carioca", "Cereais e Grãos", "kg", [1, 2], 180, 365, 8.4),
    ("Feijão preto", "Cereais e Grãos", "kg", [1], 180, 365, 9.1),
    ("Aveia em flocos", "Cereais e Grãos", "g", [170, 250, 500], 150, 270, 0.028),
    ("Granola", "Cereais e Grãos", "g", [250, 800], 120, 240, 0.045),
    ("Peito de frango", "Carnes, Aves e Pescados", "kg", [1, 2], 2, 5, 19.9),
    ("Coxa e sobrecoxa", "Carnes, Aves e Pescados", "kg", [1, 2], 2, 5, 14.5),
    ("Carne moída", "Carnes, Aves e Pescados", "g", [500, 1000], 1, 3, 0.039),
    ("Alcatra", "Carnes, Aves e Pescados", "kg", [1], 3, 5, 44.9),
    ("Linguiça toscana", "Carnes, Aves e Pescados", "kg", [1], 5, 12, 22.9),
    ("Filé de tilápia", "Carnes, Aves e Pescados", "g", [400, 800], 2, 4, 0.062),
    ("Presunto fatiado", "Carnes, Aves e Pescados", "g", [200], 5, 10, 0.055),
    ("Banana prata", "Frutas, Verduras e Legumes", "kg", [1], 3, 7, 6.5),
    ("Tomate", "Frutas, Verduras e Legumes", "kg", [1], 4, 9, 8.2),
    ("Alface crespa", "Frutas, Verduras e Legumes", "unit", [1], 3, 6, 3.5),
    ("Cebola", "Frutas, Verduras e Legumes", "kg", [1, 2], 20, 40, 5.4),
    ("Batata", "Frutas, Verduras e Legumes", "kg", [1, 2], 15, 30, 6.1),
    ("Maçã gala", "Frutas, Verduras e Legumes", "kg", [1], 10, 25, 10.9),
    ("Laranja pera", "Frutas, Verduras e Legumes", "kg", [1, 3], 10, 20, 4.8),
    ("Cenoura", "Frutas, Verduras e Legumes", "kg", [1], 12, 25, 5.2),
    ("Mamão formosa", "Frutas, Verduras e Legumes", "unit", [1], 4, 8, 9.9),
    ("Leite integral UHT", "Laticínios e Ovos", "l", [1], 90, 120, 5.3),
    ("Leite desnatado UHT", "Laticínios e Ovos", "l", [1], 90, 120, 5.6),
    ("Iogurte natural", "Laticínios e Ovos", "g", [170, 500], 15, 30, 0.021),
    ("Queijo muçarela fatiado", "Laticínios e Ovos", "g", [150, 400], 15, 30, 0.059),
    ("Requeijão cremoso", "Laticínios e Ovos", "g", [200], 30, 60, 0.042),
    ("Ovos brancos", "Laticínios e Ovos", "unit", [12, 30], 20, 30, 0.95),
    ("Manteiga com sal", "Laticínios e Ovos", "g", [200, 500], 60, 120, 0.065),
    ("Pão francês", "Padaria", "kg", [1], 1, 3, 15.9),
    ("Pão de forma", "Padaria", "g", [400, 500], 6, 12, 0.019),
    ("Bisnaguinha", "Padaria", "g", [300], 7, 14, 0.026),
    ("Bolo pronto", "Padaria", "g", [250], 10, 20, 0.04),
    ("Café torrado e moído", "Bebidas", "g", [250, 500], 120, 240, 0.07),
    ("Suco de laranja integral", "Bebidas", "l", [1, 1.5], 10, 20, 11.0),
    ("Refrigerante cola", "Bebidas", "l", [0.35, 2], 120, 180, 4.5),
    ("Água mineral", "Bebidas", "l", [0.5, 1.5, 5], 300, 540, 1.6),
    ("Cerveja pilsen", "Bebidas", "ml", [350, 600], 150, 240, 0.011),
    ("Espaguete", "Massas", "g", [500], 365, 540, 0.011),
    ("Macarrão parafuso", "Massas", "g", [500], 365, 540, 0.012),
    ("Lasanha pré-cozida", "Massas", "g", [200], 300, 450, 0.035),
    ("Molho de tomate", "Molhos, Condimentos e Temperos", "g", [300, 340], 240, 400, 0.012),
    ("Maionese", "Molhos, Condimentos e Temperos", "g", [250, 500], 150, 240, 0.024),
    ("Sal refinado", "Molhos, Condimentos e Temperos", "kg", [1], 540, 900, 3.2),
    ("Ketchup", "Molhos, Condimentos e Temperos", "g", [380], 240, 365, 0.026),
    ("Óleo de soja", "Óleos e Gorduras", "ml", [900], 240, 400, 0.0085),
    ("Azeite extravirgem", "Óleos e Gorduras", "ml", [250, 500], 400, 600, 0.09),
    ("Açúcar refinado", "Açúcares e Adoçantes", "kg", [1, 2, 5], 540, 900, 4.9),
    ("Açúcar mascavo", "Açúcares e Adoçantes", "g", [500, 1000], 300, 540, 0.016),
    ("Adoçante líquido", "Açúcares e Adoçantes", "ml", [65, 100], 365, 720, 0.12),
    ("Farinha de trigo", "Farinhas, Fermentos e Misturas", "kg", [1, 5], 120, 180, 5.8),
    ("Mistura para bolo", "Farinhas, Fermentos e Misturas", "g", [400], 180, 300, 0.016),
    ("Fermento químico", "Farinhas, Fermentos e Misturas", "g", [100, 250], 240, 365, 0.04),
    ("Atum em lata", "Conservas e Enlatados", "g", [170], 540, 900, 0.058),
    ("Milho verde em lata", "Conservas e Enlatados", "g", [200], 540, 900, 0.022),
    ("Sardinha em lata", "Conservas e Enlatados", "g", [125], 540, 900, 0.052),
    ("Biscoito cream cracker", "Biscoitos e Snacks", "g", [200, 400], 150, 270, 0.024),
    ("Biscoito recheado", "Biscoitos e Snacks", "g", [130], 150, 270, 0.025),
    ("Batata palha", "Biscoitos e Snacks", "g", [120, 400], 120, 200, 0.05),
    ("Lasanha congelada", "Congelados", "g", [600], 90, 180, 0.03),
    ("Pizza congelada", "Congelados", "g", [460], 90, 180, 0.04),
    ("Hambúrguer congelado", "Congelados", "g", [672], 120, 240, 0.03),
    ("Pão de queijo congelado", "Congelados", "g", [400, 1000], 120, 240, 0.032),
    ("Chocolate ao leite", "Doces e Sobremesas", "g", [90, 150], 180, 300, 0.07),
    ("Doce de leite", "Doces e Sobremesas", "g", [400], 180, 300, 0.025),
    ("Gelatina em pó", "Doces e Sobremesas", "g", [20], 365, 540, 0.12),
    ("Salada pronta higienizada", "Pratos Prontos", "g", [150, 250], 2, 5, 0.06),
    ("Marmita congelada", "Pratos Prontos", "g", [350], 60, 120, 0.05),
    ("Sopa pronta", "Pratos Prontos", "g", [500], 4, 8, 0.03),
    ("Tempero completo", "Outros", "g", [300], 300, 540, 0.022),
]

MARCAS = {
    "Cereais e Grãos": ["Grão Dourado", "Campo Bom", "Safra Nobre", "Terra Viva", "Bom Prato", "Celeiro Mineiro"],
    "Carnes, Aves e Pescados": ["Frigo Serra", "Granja Real", "Corte Nobre", "Mar Azul", "Sabor da Fazenda", "Pampa Carnes"],
    "Frutas, Verduras e Legumes": ["Hortifruti Local", "Fazenda Verde", "Colheita Fresca", "Sítio Alegre", "Feira Nossa", "Orgânicos do Vale"],
    "Laticínios e Ovos": ["Vale do Leite", "Laticínios Serrano", "Granja Feliz", "Leite Puro", "Montanhesa", "Queijaria Canastra"],
    "Padaria": ["Panificadora Central", "Forno Bom", "Pão da Casa", "Trigo Fino", "Padaria Estrela", "Massa Leve"],
    "Bebidas": ["Fonte Clara", "Sabor Tropical", "Café Serrano", "Cervejaria Vale", "Néctar Sul", "Serra Azul"],
    "Massas": ["Massas Italianas", "Dona Nona", "Trigo Fino", "Casa da Massa", "Pasta Fresca", "Moinho Sul"],
    "Molhos, Condimentos e Temperos": ["Tempero da Vó", "Sabor Caseiro", "Horta Fina", "Bom Gosto", "Cozinha Mineira", "Ervas Finas"],
    "Óleos e Gorduras": ["Oliva Real", "Soja Ouro", "Campo Bom", "Mediterrâneo", "Girassol Puro"],
    "Açúcares e Adoçantes": ["Doce Vida", "Usina Boa Vista", "Cana Pura", "Leve Doce", "Doce Lar"],
    "Farinhas, Fermentos e Misturas": ["Moinho Sul", "Dona Nona", "Fermento Real", "Trigo Fino", "Bolo Fácil", "Farinha Boa"],
    "Conservas e Enlatados": ["Mar Azul", "Conservas do Vale", "Bom Prato", "Pescador", "Lata Nobre", "Horta Fina"],
    "Biscoitos e Snacks": ["Crocante", "Biscoitos Aurora", "Petisco Bom", "Dona Nona", "Biscoitos Sul", "Croc Mix"],
    "Congelados": ["Frio Bom", "Congelados da Serra", "Pronto Já", "Granja Real", "Sabor Gelado", "Forno Pronto"],
    "Doces e Sobremesas": ["Doce Minas", "Cacau Nobre", "Doce Vida", "Sobremesa Fácil", "Confeitaria Real", "Gelato Bom"],
    "Pratos Prontos": ["Pronto Já", "Cozinha da Casa", "Fazenda Verde", "Marmita Fit", "Sabor Natural", "Prato Feito"],
    "Outros": ["Tempero da Vó", "Sabor Caseiro", "Bom Gosto", "Cozinha Mineira", "Ervas Finas"],
}

# chance de um item da categoria vencer antes de ser consumido (as demais: 4%)
DESPERDICIO = {"Frutas, Verduras e Legumes": 0.30, "Padaria": 0.28, "Pratos Prontos": 0.25,
               "Laticínios e Ovos": 0.18, "Carnes, Aves e Pescados": 0.14, "Bebidas": 0.06,
               "Congelados": 0.05, "Biscoitos e Snacks": 0.05}
# chance de o item ser registrado sem data de validade (granel, feira, padaria)
SEM_VALIDADE = {"Frutas, Verduras e Legumes": 0.40, "Padaria": 0.30, "Carnes, Aves e Pescados": 0.06}

# ------------------------------------------------------------------ geografia
# UF: DDD, população (milhões, peso), cidades [(nome, lat, lon, prefixo CEP, peso dentro da UF)]
UFS = {
    "AC": (68, 0.8, [("Rio Branco", -9.97, -67.81, "699", 1)]),
    "AL": (82, 3.1, [("Maceió", -9.67, -35.74, "57", 3), ("Arapiraca", -9.75, -36.66, "573", 1)]),
    "AP": (96, 0.7, [("Macapá", 0.03, -51.07, "689", 1)]),
    "AM": (92, 3.9, [("Manaus", -3.12, -60.02, "690", 1)]),
    "BA": (71, 14.1, [("Salvador", -12.97, -38.50, "40", 4), ("Feira de Santana", -12.27, -38.97, "440", 1.5),
                      ("Vitória da Conquista", -14.86, -40.84, "450", 1)]),
    "CE": (85, 8.8, [("Fortaleza", -3.73, -38.53, "60", 4), ("Juazeiro do Norte", -7.21, -39.32, "630", 1),
                     ("Sobral", -3.69, -40.35, "620", 0.7)]),
    "DF": (61, 2.8, [("Brasília", -15.79, -47.88, "70", 1)]),
    "ES": (27, 3.8, [("Vitória", -20.32, -40.34, "290", 1.5), ("Vila Velha", -20.33, -40.29, "291", 1.5),
                     ("Serra", -20.13, -40.31, "291", 1)]),
    "GO": (62, 7.1, [("Goiânia", -16.68, -49.25, "74", 3), ("Aparecida de Goiânia", -16.82, -49.24, "749", 1.2),
                     ("Anápolis", -16.33, -48.95, "751", 1)]),
    "MA": (98, 6.8, [("São Luís", -2.53, -44.30, "65", 3), ("Imperatriz", -5.53, -47.49, "659", 1)]),
    "MT": (65, 3.7, [("Cuiabá", -15.60, -56.10, "78", 2), ("Rondonópolis", -16.47, -54.64, "787", 1)]),
    "MS": (67, 2.8, [("Campo Grande", -20.47, -54.62, "79", 3), ("Dourados", -22.22, -54.81, "798", 1)]),
    "MG": (31, 20.5, [("Belo Horizonte", -19.92, -43.94, "30", 4), ("Uberlândia", -18.92, -48.28, "384", 1.5),
                      ("Contagem", -19.93, -44.05, "321", 1.2), ("Juiz de Fora", -21.76, -43.35, "360", 1.2),
                      ("Montes Claros", -16.73, -43.86, "394", 0.8)]),
    "PA": (91, 8.1, [("Belém", -1.46, -48.50, "66", 3), ("Ananindeua", -1.37, -48.37, "670", 1.2),
                     ("Santarém", -2.44, -54.71, "680", 0.8)]),
    "PB": (83, 4.0, [("João Pessoa", -7.12, -34.86, "58", 2), ("Campina Grande", -7.23, -35.88, "584", 1)]),
    "PR": (41, 11.4, [("Curitiba", -25.43, -49.27, "80", 4), ("Londrina", -23.31, -51.16, "860", 1.5),
                      ("Maringá", -23.42, -51.94, "870", 1.2), ("Cascavel", -24.96, -53.46, "858", 0.8)]),
    "PE": (81, 9.1, [("Recife", -8.05, -34.88, "50", 4), ("Jaboatão dos Guararapes", -8.11, -35.01, "540", 1.5),
                     ("Caruaru", -8.28, -35.98, "550", 1), ("Petrolina", -9.39, -40.50, "563", 0.8)]),
    "PI": (86, 3.3, [("Teresina", -5.09, -42.80, "64", 3), ("Parnaíba", -2.90, -41.78, "642", 0.6)]),
    "RJ": (21, 16.1, [("Rio de Janeiro", -22.91, -43.17, "20", 6), ("Niterói", -22.88, -43.10, "240", 1.2),
                      ("Duque de Caxias", -22.79, -43.31, "25", 1.5), ("Petrópolis", -22.51, -43.18, "256", 0.7)]),
    "RN": (84, 3.3, [("Natal", -5.79, -35.21, "59", 3), ("Mossoró", -5.19, -37.34, "596", 1)]),
    "RS": (51, 10.9, [("Porto Alegre", -30.03, -51.23, "90", 4), ("Caxias do Sul", -29.17, -51.18, "950", 1.3),
                      ("Pelotas", -31.77, -52.34, "960", 1), ("Santa Maria", -29.69, -53.81, "971", 0.8)]),
    "RO": (69, 1.6, [("Porto Velho", -8.76, -63.90, "768", 1)]),
    "RR": (95, 0.6, [("Boa Vista", 2.82, -60.67, "693", 1)]),
    "SC": (48, 7.6, [("Florianópolis", -27.60, -48.55, "880", 2), ("Joinville", -26.30, -48.85, "892", 2),
                     ("Blumenau", -26.92, -49.07, "890", 1.3), ("Chapecó", -27.10, -52.62, "898", 0.8)]),
    "SP": (11, 44.4, [("São Paulo", -23.55, -46.63, "0", 10), ("Campinas", -22.91, -47.06, "130", 2),
                      ("Guarulhos", -23.46, -46.53, "07", 1.8), ("São José dos Campos", -23.18, -45.89, "122", 1.2),
                      ("Ribeirão Preto", -21.18, -47.81, "140", 1.2), ("Sorocaba", -23.50, -47.46, "180", 1.1),
                      ("Santos", -23.96, -46.33, "110", 0.9)]),
    "SE": (79, 2.2, [("Aracaju", -10.91, -37.07, "49", 1)]),
    "TO": (63, 1.5, [("Palmas", -10.18, -48.33, "77", 1)]),
}

REGIAO = {**dict.fromkeys(["AC", "AP", "AM", "PA", "RO", "RR", "TO"], "Norte"),
          **dict.fromkeys(["AL", "BA", "CE", "MA", "PB", "PE", "PI", "RN", "SE"], "Nordeste"),
          **dict.fromkeys(["DF", "GO", "MT", "MS"], "Centro-Oeste"),
          **dict.fromkeys(["ES", "MG", "RJ", "SP"], "Sudeste"),
          **dict.fromkeys(["PR", "RS", "SC"], "Sul")}
# padrões regionais simulados: peso da categoria na escolha dos alimentos (demais: 1)
PREFERENCIA_REGIAO = {
    "Norte": {"Frutas, Verduras e Legumes": 2.0, "Carnes, Aves e Pescados": 1.5, "Cereais e Grãos": 1.3},
    "Nordeste": {"Frutas, Verduras e Legumes": 1.8, "Cereais e Grãos": 1.7, "Laticínios e Ovos": 0.7},
    "Centro-Oeste": {"Carnes, Aves e Pescados": 2.0, "Cereais e Grãos": 1.4},
    "Sudeste": {"Pratos Prontos": 2.0, "Congelados": 1.7, "Padaria": 1.4, "Laticínios e Ovos": 1.3},
    "Sul": {"Carnes, Aves e Pescados": 2.3, "Laticínios e Ovos": 1.6, "Bebidas": 1.3},
}
# multiplicador da chance de vencer por região (clima e hábito de compra)
DESPERDICIO_REGIAO = {"Norte": 1.35, "Nordeste": 1.15, "Centro-Oeste": 1.0, "Sudeste": 0.95, "Sul": 0.8}
# moradores por household e peso
MORADORES = ([1, 2, 3, 4, 5, 6], [0.16, 0.27, 0.25, 0.19, 0.09, 0.04])
# status por tipo de perfil: (ACTIVE, INACTIVE) - o resto é BLOCKED
STATUS = {"HOUSEHOLD": (0.86, 0.97), "COMPANY": (0.90, 0.98), "STORE": (0.92, 0.99)}


def ean13(corpo12: str) -> str:
    soma = sum(int(d) * (3 if i % 2 else 1) for i, d in enumerate(corpo12))
    return corpo12 + str((10 - soma % 10) % 10)


def montar_catalogo() -> list[dict]:
    """~520 SKUs determinísticos: produto x marca x embalagem."""
    rng = random.Random(7)
    skus = []
    for nome, cat, uni, embalagens, vmin, vmax, preco in PRODUTOS:
        marcas = rng.sample(MARCAS[cat], k=min(len(MARCAS[cat]), {1: 6, 2: 5}.get(len(embalagens), 3)))
        for marca in marcas:
            fator = rng.uniform(0.85, 1.3)  # marca premium x econômica
            for emb in embalagens:
                skus.append({"nome": nome, "categoria": cat, "unidade": uni, "embalagem": emb, "marca": marca,
                             "vmin": vmin, "vmax": vmax, "preco": round(preco * emb * fator, 2)})
    # corta variações de marca até o ALVO, mantendo todos os produtos
    while len(skus) > ALVO:
        contagem = {}
        for sku in skus:
            contagem[sku["nome"]] = contagem.get(sku["nome"], 0) + 1
        candidatos = [i for i, sku in enumerate(skus) if contagem[sku["nome"]] > 3]
        skus.pop(rng.choice(candidatos))
    for i, sku in enumerate(skus):
        sku["gtin"] = ean13(f"{GTIN_PREFIXO}{i:07d}")
    return skus


class SimulacaoBI:
    def __init__(self, ref: date, foods: dict, planos: list, alocar):
        self.rng = random.Random(2026)
        self.fake = Faker("pt_BR")
        self.fake.seed_instance(2026)
        self.ref = datetime.combine(ref, time(23, 59))
        self.inicio = self.ref - timedelta(days=JANELA)
        self.foods = foods        # food_id -> sku (dict de montar_catalogo)
        self.planos = planos      # [(id, nome, preco, limite)] ordenados por preço
        self.alocar = alocar      # alocar(tabela, n) -> ids reservados nas sequences
        self.por_categoria = {}
        for fid, sku in foods.items():
            self.por_categoria.setdefault(sku["categoria"], []).append(fid)
        self.pg = {t: [] for t in ["address", "profile", "profile_phone", "auth_method", "company",
                                   "store", "payment", "pantry_item", "pantry_product_setting"]}
        self.hist = []            # bi_hist.registro_estoque

    # ---------------------------------------------------------------- utilidades
    def _entre(self, a: datetime, b: datetime) -> datetime:
        return a + (b - a) * self.rng.random() if b > a else a

    def _cadastro(self) -> datetime:
        # raiz da uniforme: mais cadastros nos meses recentes (crescimento da base)
        return self.inicio + timedelta(days=JANELA * self.rng.random() ** 0.6, hours=self.rng.randint(8, 21),
                                       minutes=self.rng.randint(0, 59))

    def _uf(self) -> str:
        return self.rng.choices(list(UFS), [u[1] for u in UFS.values()])[0]

    def _cidade(self, uf: str):
        cidades = UFS[uf][2]
        return self.rng.choices(cidades, [c[4] for c in cidades])[0]

    # ---------------------------------------------------------------- perfis
    def _perfis(self, tipo: str, ufs: list, nomes=None, cadastro_ate=None) -> list[dict]:
        pids, aids = self.alocar("profile", len(ufs)), self.alocar("address", len(ufs))
        perfis = []
        for i, (pid, aid, uf) in enumerate(zip(pids, aids, ufs, strict=True)):
            cidade, lat, lon, cep, _ = self._cidade(uf)
            self.pg["address"].append({
                "id": aid, "neighborhood": self.fake.bairro()[:100], "street": self.fake.street_name()[:150],
                "number": str(self.rng.randint(1, 4000)),
                "cep": cep + str(self.rng.randint(0, 10**8 - 1)).zfill(8)[len(cep):],
                "city": cidade, "state": uf,
                "latitude": round(lat + self.rng.gauss(0, 0.035), 6), "longitude": round(lon + self.rng.gauss(0, 0.035), 6),
            })
            cadastro = (self.inicio + timedelta(days=self.rng.uniform(0, cadastro_ate), hours=self.rng.randint(8, 18))
                        if cadastro_ate else self._cadastro())
            ativo, inativo = STATUS[tipo]
            sorteio = self.rng.random()
            status = "ACTIVE" if sorteio < ativo else ("INACTIVE" if sorteio < inativo else "BLOCKED")
            if nomes:
                nome = nomes[i]
            else:
                nome = self.fake.name() if tipo == "HOUSEHOLD" else self.fake.company()
            self.pg["profile"].append({"id": pid, "address_id": aid, "email": f"{tipo.lower()}{pid}{DOMINIO}",
                                       "name": nome[:150], "created_at": cadastro, "type": tipo, "status": status})
            ddd = UFS[uf][0]
            self.pg["profile_phone"].append({"profile_id": pid, "phone": f"+55{ddd}9{self.rng.randint(10**7, 10**8 - 1)}"})
            if self.rng.random() < (0.04 if tipo == "HOUSEHOLD" else 0.15):  # telefone fixo
                self.pg["profile_phone"].append({"profile_id": pid, "phone": f"+55{ddd}3{self.rng.randint(10**6, 10**7 - 1)}"})
            google = self.rng.random() < (0.62 if tipo == "HOUSEHOLD" else 0.3)
            self.pg["auth_method"].append({"profile_id": pid, "provider": "GOOGLE" if google else "PASSWORD",
                                           "credential": self.fake.uuid4(), "created_at": cadastro})
            if self.rng.random() < 0.04:  # vinculou o segundo método depois
                self.pg["auth_method"].append({"profile_id": pid, "provider": "PASSWORD" if google else "GOOGLE",
                                               "credential": self.fake.uuid4(),
                                               "created_at": self._entre(cadastro, self.ref)})
            fim = self.ref if status == "ACTIVE" else self._entre(cadastro + timedelta(days=20), self.ref)
            perfis.append({"id": pid, "uf": uf, "cidade": cidade, "nome": nome, "cadastro": cadastro, "fim": fim})
        return perfis

    def _peso(self, uf: str, fid) -> float:
        return PREFERENCIA_REGIAO[REGIAO[uf]].get(self.foods[fid]["categoria"], 1.0)

    def _preferidos(self, uf: str, k: int) -> list:
        # amostra ponderada sem reposição (Efraimidis-Spirakis)
        chave = {f: self.rng.random() ** (1 / self._peso(uf, f)) for f in self.foods}
        return sorted(self.foods, key=chave.get, reverse=True)[:k]

    def gerar(self):
        casas = self._perfis("HOUSEHOLD", [self._uf() for _ in range(VOL["household"])])
        for h in casas:
            h["moradores"] = self.rng.choices(*MORADORES)[0]
            h["propensao"] = self.rng.lognormvariate(0, 0.45)       # descuido com validade
            h["prefs"] = self._preferidos(h["uf"], self.rng.randint(14, 30))
        self._empresas()
        for h in casas:
            self._compras(h)
        self._reduzir("pantry_item")
        self._minimos(casas)  # depois da amostra: mínimo coerente com o estoque que ficou
        self._reduzir("pantry_product_setting")
        self._reduzir_hist()
        return self

    def _reduzir(self, tabela: str):
        """Amostra aleatória até o ALVO (mantém as proporções dos KPIs)."""
        if len(self.pg[tabela]) > ALVO:
            self.pg[tabela] = self.rng.sample(self.pg[tabela], ALVO)

    def _reduzir_hist(self):
        if len(self.hist) > ALVO:
            self.hist = sorted(self.rng.sample(self.hist, ALVO), key=lambda r: r["event_date"])

    # ---------------------------------------------------------------- empresas
    def _empresas(self):
        # empresas entram nos primeiros meses: ~10 mensalidades cada (>= 500 pagamentos)
        empresas = self._perfis("COMPANY", [self._uf() for _ in range(VOL["company"])], cadastro_ate=75)
        pesos = [0.5, 0.35, 0.15] if len(self.planos) == 3 else None
        for emp, cid in zip(empresas, self.alocar("company", len(empresas)), strict=True):
            idx = self.rng.choices(range(len(self.planos)), pesos)[0]
            emp.update(cid=cid, plano=self.planos[idx], lojas=0, upgrade=None)
            if idx + 1 < len(self.planos) and self.rng.random() < 0.12:  # fez upgrade no meio do período
                emp["upgrade"] = (self._entre(emp["cadastro"], emp["fim"]).date(), self.planos[idx + 1])
            atual = emp["upgrade"][1] if emp["upgrade"] else emp["plano"]
            self.pg["company"].append({"id": cid, "plan_id": atual[0], "profile_id": emp["id"],
                                       "cnpj": "".join(filter(str.isdigit, self.fake.unique.cnpj()))})
            self._mensalidades(emp)

        # toda empresa tem pelo menos 1 loja (matriz); o resto vai para quem tem limite
        donos = list(empresas)
        while len(donos) < VOL["store"]:
            emp = self.rng.choice(empresas)
            limite = (emp["upgrade"][1] if emp["upgrade"] else emp["plano"])[3]
            if donos.count(emp) < limite:
                donos.append(emp)
        ufs, nomes = [], []
        for emp in donos:
            emp["lojas"] += 1
            uf = emp["uf"] if self.rng.random() < 0.8 else self._uf()
            ufs.append(uf)
            nomes.append(f"{emp['nome']} - Loja {emp['lojas']:02d}")
        lojas = self._perfis("STORE", ufs, nomes)
        for emp, loja in zip(donos, lojas, strict=True):
            self.pg["store"].append({"company_id": emp["cid"], "profile_id": loja["id"],
                                     "cnpj": "".join(filter(str.isdigit, self.fake.unique.cnpj()))})

    def _mensalidades(self, emp: dict):
        dia = min(emp["cadastro"].day, 28)
        inicio = emp["cadastro"].date().replace(day=dia)
        bom_pagador = self.rng.random() < 0.8
        while inicio <= emp["fim"].date():
            proximo = (inicio.replace(day=1) + timedelta(days=32)).replace(day=dia)
            plano = emp["plano"]
            if emp["upgrade"] and inicio >= emp["upgrade"][0]:
                plano = emp["upgrade"][1]
            vencimento = inicio + timedelta(days=10)
            status, pago = "PENDING", None
            if vencimento <= self.ref.date():
                sorteio = self.rng.random()
                pontual = 0.92 if bom_pagador else 0.6
                atraso = -self.rng.randint(0, 9) if self.rng.random() < pontual else self.rng.randint(1, 25)
                dia_pago = vencimento + timedelta(days=atraso)
                if sorteio < 0.03:
                    status = "CANCELLED"
                elif sorteio < (0.06 if bom_pagador else 0.2) or dia_pago > self.ref.date():
                    status = "OVERDUE"
                else:
                    status, pago = "PAID", datetime.combine(dia_pago, time(self.rng.randint(8, 20), self.rng.randint(0, 59)))
            self.pg["payment"].append({
                "due_date": vencimento, "billing_period_start": inicio, "billing_period_end": proximo - timedelta(days=1),
                "payment_status": status, "company_id": emp["cid"], "plan_id": plano[0],
                "amount": plano[2], "paid_at": pago, "created_at": datetime.combine(inicio, time(6)),
                "updated_at": pago or datetime.combine(min(vencimento, self.ref.date()), time(6)),
            })
            inicio = proximo

    # ---------------------------------------------------------------- despensa
    def _compras(self, h: dict):
        """Cada item comprado é consumido, vence e é descartado, ou continua na despensa hoje."""
        t = h["cadastro"]
        intervalo = (5, 12) if h["moradores"] >= 4 else (7, 16)
        limite = min(self.ref, h["fim"])
        while t < h["fim"]:
            for _ in range(self.rng.randint(1, 3 + h["moradores"] // 2)):
                fid = self.rng.choices(h["prefs"], [self._peso(h["uf"], f) for f in h["prefs"]])[0]
                sku = self.foods[fid]
                cat, vmin, vmax = sku["categoria"], sku["vmin"], sku["vmax"]
                qtd = max(1, min(12, round(self.rng.uniform(0.6, 1.4) * (1 + h["moradores"] / 3))))
                vida = self.rng.randint(vmin, vmax)
                validade_real = (t + timedelta(days=vida)).date()
                validade = None if self.rng.random() < SEM_VALIDADE.get(cat, 0.02) else validade_real
                meses_de_app = (t - h["cadastro"]).days / 30
                aprendizado = max(0.45, 1 - 0.035 * meses_de_app)  # usa o app -> desperdiça menos
                solteiro = 1.25 if h["moradores"] == 1 else 1.0
                p_vencer = min(0.9, DESPERDICIO.get(cat, 0.04) * DESPERDICIO_REGIAO[REGIAO[h["uf"]]]
                               * h["propensao"] * aprendizado * solteiro)
                if self.rng.random() < p_vencer:
                    esquecido = self.rng.randint(10, 90) if self.rng.random() < 0.5 else self.rng.randint(0, 6)
                    descarte = datetime.combine(validade_real + timedelta(days=esquecido), time(self.rng.randint(7, 22)))
                    if descarte <= limite:
                        self._record(h["id"], t, validade, descarte, "item_expired", fid, qtd, round(qtd * sku["preco"], 2))
                        continue
                    if h["fim"] < self.ref:  # perfil saiu do app: item some sem registro
                        continue
                else:
                    janela = min(max(vida, 1), 120 if vmax >= 180 else 40)
                    consumo = t + timedelta(days=self.rng.uniform(0.1, 0.95) * janela)
                    if consumo <= limite:
                        self._record(h["id"], t, validade, consumo, "item_consumed", fid, 0, 0.0, consumido=qtd)
                        continue
                    if h["fim"] < self.ref:
                        continue
                self.pg["pantry_item"].append({"food_id": fid, "profile_id": h["id"], "quantity": qtd,
                                               "expiry_date": validade, "created_at": t})
            t += timedelta(days=self.rng.uniform(*intervalo), hours=self.rng.uniform(-3, 3))

    def _record(self, conta, compra, validade, quando, tipo, fid, descartado, perda, consumido=0):
        self.hist.append({"profile_id": conta, "food_id": fid, "event_type": tipo, "event_date": quando,
                          "purchase_date": compra, "expiry_date": validade,
                          "consumed_quantity": consumido, "discarded_quantity": descartado,
                          "estimated_loss": perda})

    def _minimos(self, casas: list):
        estoque = {}
        for i in self.pg["pantry_item"]:
            estoque[(i["profile_id"], i["food_id"])] = estoque.get((i["profile_id"], i["food_id"]), 0) + i["quantity"]
        for h in casas:
            if h["fim"] < self.ref and self.rng.random() < 0.5:
                continue  # parte dos que saíram nunca configurou mínimo
            em_casa = [f for f in h["prefs"] if (h["id"], f) in estoque]
            fora = [f for f in h["prefs"] if (h["id"], f) not in estoque]
            escolhidos = list(em_casa)  # monitora o que tem em casa
            if self.rng.random() < 0.2:  # e às vezes algo que acabou
                escolhidos += self.rng.sample(fora, k=min(len(fora), 1))
            disciplinado = self.rng.random() < 0.8  # mantém a despensa acima do mínimo
            for fid in escolhidos:
                atual = estoque.get((h["id"], fid), 0)
                if disciplinado and atual:
                    minimo = max(1, atual - self.rng.randint(0, 3))
                else:
                    minimo = atual + self.rng.randint(1, 3)
                if self.rng.random() < 0.06:
                    minimo = 0  # configurou e desligou o alerta
                criado = self._entre(h["cadastro"], min(h["fim"], self.ref))
                self.pg["pantry_product_setting"].append({"food_id": fid, "profile_id": h["id"], "minimum_quantity": minimo,
                                                          "created_at": criado,
                                                          "updated_at": self._entre(criado, min(h["fim"], self.ref))})


# ------------------------------------------------------------------ carga
HIST_DDL = """
CREATE SCHEMA IF NOT EXISTS bi_hist;
CREATE TABLE IF NOT EXISTS bi_hist.registro_estoque (
    id                 SERIAL PRIMARY KEY,
    profile_id         INTEGER NOT NULL REFERENCES profile(id) ON DELETE CASCADE,
    food_id            INTEGER NOT NULL REFERENCES food(id),
    event_type         VARCHAR(30) NOT NULL CHECK (event_type IN ('item_consumed', 'item_expired')),
    event_date         TIMESTAMP NOT NULL,
    purchase_date      TIMESTAMP NOT NULL,
    expiry_date        DATE,
    consumed_quantity  INTEGER NOT NULL DEFAULT 0 CHECK (consumed_quantity >= 0),
    discarded_quantity INTEGER NOT NULL DEFAULT 0 CHECK (discarded_quantity >= 0),
    estimated_loss     DECIMAL(10,2) NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS ix_registro_estoque_profile ON bi_hist.registro_estoque (profile_id);
CREATE INDEX IF NOT EXISTS ix_registro_estoque_data ON bi_hist.registro_estoque (event_date);
"""

LIMPEZA_SQL = """
DELETE FROM payment WHERE company_id IN
    (SELECT c.id FROM company c JOIN profile p ON p.id = c.profile_id WHERE p.email LIKE %(m)s);
DELETE FROM store   WHERE profile_id IN (SELECT id FROM profile WHERE email LIKE %(m)s);
DELETE FROM store   WHERE company_id IN
    (SELECT c.id FROM company c JOIN profile p ON p.id = c.profile_id WHERE p.email LIKE %(m)s);
DELETE FROM company WHERE profile_id IN (SELECT id FROM profile WHERE email LIKE %(m)s);
CREATE TEMP TABLE end_bi ON COMMIT DROP AS SELECT address_id FROM profile WHERE email LIKE %(m)s;
DELETE FROM profile WHERE email LIKE %(m)s;  -- cascata: pantry_item, settings, telefones, auth, bi_hist
DELETE FROM address a WHERE a.id IN (SELECT address_id FROM end_bi)
    AND NOT EXISTS (SELECT 1 FROM profile p WHERE p.address_id = a.id);
-- catálogo da versão anterior do dataload BI (32 itens "NexUs BI"), se não estiver em uso
DELETE FROM food f WHERE f.product_brand = 'NexUs BI' AND f.gtin LIKE '29%%'
    AND NOT EXISTS (SELECT 1 FROM pantry_item i WHERE i.food_id = f.id)
    AND NOT EXISTS (SELECT 1 FROM pantry_product_setting s WHERE s.food_id = f.id);
"""


def executar(pg):
    ref = date.fromisoformat(os.getenv("BI_DATA_REF") or datetime.now(ZoneInfo("America/Sao_Paulo")).strftime("%Y-%m-%d"))
    with pg.conn.cursor() as cur:
        cur.execute(HIST_DDL)
        cur.execute(LIMPEZA_SQL, {"m": "%" + DOMINIO})

        # categorias, planos e alimentos: reaproveita os existentes, cria só o que falta
        execute_values(cur, "INSERT INTO category (category_name) VALUES %s ON CONFLICT DO NOTHING",
                       [(c,) for c in CATEGORIES])
        execute_values(cur, "INSERT INTO plan (plan_name, plan_price, store_limit, description) VALUES %s "
                            "ON CONFLICT (plan_name) DO NOTHING",
                       [(p["plan_name"], p["plan_price"], p["store_limit"], p["description"]) for p in PLANS])
        cur.execute("SELECT category_name, id FROM category")
        cat = dict(cur.fetchall())
        catalogo = montar_catalogo()
        execute_values(cur, "INSERT INTO food (name, category_id, product_brand, package_quantity, unit_of_measure, gtin) "
                            "VALUES %s ON CONFLICT (gtin) DO UPDATE SET name = EXCLUDED.name, category_id = EXCLUDED.category_id, "
                            "product_brand = EXCLUDED.product_brand, package_quantity = EXCLUDED.package_quantity, "
                            "unit_of_measure = EXCLUDED.unit_of_measure",
                       [(s["nome"], cat[s["categoria"]], s["marca"], s["embalagem"], s["unidade"], s["gtin"])
                        for s in catalogo], page_size=1000)
        # SKUs de execuções anteriores que saíram do catálogo (só se ninguém usa)
        cur.execute("DELETE FROM food f WHERE f.gtin LIKE %s AND NOT (f.gtin = ANY(%s)) "
                    "AND NOT EXISTS (SELECT 1 FROM pantry_item i WHERE i.food_id = f.id) "
                    "AND NOT EXISTS (SELECT 1 FROM pantry_product_setting s WHERE s.food_id = f.id) "
                    "AND NOT EXISTS (SELECT 1 FROM bi_hist.registro_estoque r WHERE r.food_id = f.id)",
                    (GTIN_PREFIXO + "%", [s["gtin"] for s in catalogo]))
        cur.execute("SELECT gtin, id FROM food WHERE gtin LIKE %s", (GTIN_PREFIXO + "%",))
        gtin_id = dict(cur.fetchall())
        foods = {gtin_id[s["gtin"]]: s for s in catalogo}
        cur.execute("SELECT id, plan_name, plan_price::float, store_limit FROM plan WHERE is_active ORDER BY plan_price, id")
        planos = cur.fetchall()

        def alocar(tabela, n):
            cur.execute(f"SELECT nextval(pg_get_serial_sequence('{tabela}', 'id')) FROM generate_series(1, %s)", (n,))
            return [r[0] for r in cur.fetchall()]

        sim = SimulacaoBI(ref, foods, planos, alocar).gerar()
        for tabela, linhas in [*sim.pg.items(), ("bi_hist.registro_estoque", sim.hist)]:
            colunas = list(dict.fromkeys(c for linha in linhas for c in linha))
            execute_values(cur, f"INSERT INTO {tabela} ({', '.join(colunas)}) VALUES %s",
                           [tuple(linha.get(c) for c in colunas) for linha in linhas], page_size=1000)
            print(f"[BI] {tabela}: {len(linhas)}")
        print(f"[BI] food (catálogo BI): {len(foods)}")
    pg.commit()
