CATEGORIES = [
    "Laticinios",
    "Carnes",
    "Frutas",
    "Verduras",
    "Bebidas",
    "Massas",
    "Sobremesas",
    "Outros",
]

PLANS = [
    {
        "plan_name": "Ceris",
        "plan_price": 69.99,
        "store_limit": 3,
        "description": (
            "Plano de entrada. Recomendacoes basicas de produtos na lista, "
            "dashboard basico com produtos do estoque e insights sobre "
            "vendas em regioes proximas."
        ),
        "is_active": True,
    },
    {
        "plan_name": "Enterprise",
        "plan_price": 199.99,
        "store_limit": 10,
        "description": (
            "Plano para maior capacidade de analise. Recomendacoes aprimoradas, "
            "visualizacao de filiais proximas, insights regionais, produtos mais "
            "desejados por periodo/regiao e dashboard analitico do estoque."
        ),
        "is_active": True,
    },
    {
        "plan_name": "Exclusive",
        "plan_price": 499.99,
        "store_limit": 9999,
        "description": (
            "Plano mais completo. Recomendacoes avancadas, IA de receitas, "
            "filiais ilimitadas, insights regionais, campanhas promocionais "
            "exclusivas e dashboard estrategico do estoque."
        ),
        "is_active": True,
    },
]
FOOD_NAMES = [
    "Sal grosso", "Picanha", "Frango", "Arroz", "Feijao",
    "Farofa", "Vinagrete", "Cerveja", "Refrigerante", "Pao de alho",
]

def get_all_fixed() -> dict:
    return {
        "category": [{"category_name": c} for c in CATEGORIES],
        "plan": PLANS,
    }
