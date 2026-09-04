import random

from ..config import TAMANHOS
from ..core.ids import RANGES
from ..core.mongo_ids import EVENT_OIDS, RECIPE_OIDS
from ..core.rng import get_faker
from ..seed import FOOD_NAMES

fake = get_faker()

HOUSEHOLD_IDS = list(RANGES["household"])


def _household_id() -> int:
    return random.choice(HOUSEHOLD_IDS)




def _quantity() -> str:
    return f"{random.randint(100, 5000)}g" if random.random() < 0.5 else f"{random.randint(1, 5)}kg"


def build_recipes() -> list[dict]:
    return [
        {
            "_id": RECIPE_OIDS[i],
            "title": fake.sentence(nb_words=3),
            "serving_size": random.randint(2, 12),
            "ingredients": [
                {
                    "food_id": random.randint(1, TAMANHOS["food"]),
                    "required_quantity": _quantity(),
                    "mandatory": fake.boolean(),
                    "possible_substitutes": random.sample(
                        range(1, TAMANHOS["food"] + 1), k=random.randint(0, 2)
                    ),
                }
                for _ in range(random.randint(3, 8))
            ],
            "instructions": fake.paragraph(),
            "is_liked": fake.boolean(),
            "created_by": fake.random_element(elements=["ai", "user"]),
        }
        for i in range(TAMANHOS["recipe"])
    ]


def build_events() -> list[dict]:
    return [
        {
            "_id": EVENT_OIDS[i],
            "household_id": _household_id(),
            "title": fake.sentence(nb_words=4),
            "description": fake.sentence(),
            "date": fake.date_time_this_year(),
            "duration": random.choice([60, 120, 180, 240, 360]),
            "local": fake.city(),
            "qtd_people": random.randint(2, 40),
            "recipes": [
                {
                    "recipe_id": random.choice(RECIPE_OIDS),
                    "title": fake.sentence(nb_words=2),
                    "ingredients": [
                        {
                            "food_id": random.randint(1, TAMANHOS["food"]),
                            "ingredient": random.choice(FOOD_NAMES),
                            "total_quantity": _quantity(),
                            "has_enough": fake.boolean(),
                        }
                        for _ in range(random.randint(1, 4))
                    ],
                }
                for _ in range(random.randint(1, 3))
            ],
        }
        for i in range(TAMANHOS["event"])
    ]


def build_recipe_accounts() -> list[dict]:
    return [
        {
            "id_recipe": random.choice(RECIPE_OIDS),
            "id_account": _household_id(),
            "created_at": fake.date_time_this_year(),
        }
        for _ in range(TAMANHOS["recipe_account"])
    ]


def build_conversations() -> list[dict]:
    return [
        {
            "account_id": _household_id(),
            "historico": [
                {"role": "user", "content": fake.sentence()},
                {"role": "assistant", "content": fake.sentence()},
            ],
            "created_at": fake.date_time_this_year(),
            "updated_at": fake.date_time_this_year(),
        }
        for _ in range(TAMANHOS["conversation"])
    ]


def build_knowledge() -> list[dict]:
    return [
        {
            "household_id": _household_id(),
            "source_agent": fake.random_element(elements=["chat", "recipes", "events", "stock"]),
            "knowledge_type": fake.random_element(
                elements=[
                    "preference",
                    "recipe_feedback",
                    "event_estimation_error",
                    "event_estimation_success",
                ]
            ),
            "fact": fake.sentence(),
            "context": {"origin_event_id": random.choice(EVENT_OIDS)},
            "ai_guideline": {
                "identified_triggers": [fake.word() for _ in range(random.randint(1, 3))],
                "recommended_action": fake.sentence(),
            },
        }
        for _ in range(TAMANHOS["knowledge"])
    ]


def build_records() -> list[dict]:
    return [
        {
            "account_id": _household_id(),
            "date": fake.date_time_this_year(),
            "event_type": fake.random_element(
                elements=[
                    "item_consumed",
                    "item_expired",
                    "recipe_status_changed",
                    "shopping_list_added",
                ]
            ),
            "details": {
                "food_id": random.randint(1, TAMANHOS["food"]),
                "discarded_quantity": random.randint(1, 10),
                "estimated_loss": round(random.uniform(1.0, 50.0), 2),
            },
        }
        for _ in range(TAMANHOS["record"])
    ]


def build_shopping_lists() -> list[dict]:
    return [
        {
            "household_id": _household_id(),
            "event_id": random.choice(EVENT_OIDS),
            "title": fake.sentence(nb_words=3),
            "items": [
                {
                    "food_id": random.randint(1, TAMANHOS["food"]),
                    "ingredient": random.choice(FOOD_NAMES),
                    "quantity": _quantity(),
                    "purchased": fake.boolean(),
                }
                for _ in range(random.randint(2, 6))
            ],
        }
        for _ in range(TAMANHOS["shopping_list"])
    ]


def build_metrics() -> list[dict]:
    return [
        {
            "trace_id": fake.uuid4().replace("-", "")[:8],
            "route": fake.random_element(elements=["eventos", "receitas", "estoque", "conversa"]),
            "started_at": fake.date_time_this_year(),
            "finished_at": fake.date_time_this_year(),
            "duration_ms": round(random.uniform(50.0, 2000.0), 1),
            "tool_calls": random.randint(0, 8),
            "error": fake.boolean(),
        }
        for _ in range(TAMANHOS["metric"])
    ]


def build_tool_metrics() -> list[dict]:
    return [
        {
            "trace_id": fake.uuid4().replace("-", "")[:8],
            "tool_name": fake.random_element(
                elements=["get_stock", "get_recipe", "get_event", "create_shopping_list"]
            ),
            "started_at": fake.date_time_this_year(),
            "finished_at": fake.date_time_this_year(),
            "duration_ms": round(random.uniform(10.0, 500.0), 1),
            "success": fake.boolean(),
        }
        for _ in range(TAMANHOS["tool_metric"])
    ]


def build_traces() -> list[dict]:
    return [
        {
            "trace_id": fake.uuid4().replace("-", "")[:8],
            "span_name": fake.random_element(elements=["roteador", "banco", "ia", "integracao"]),
            "started_at": fake.date_time_this_year(),
            "finished_at": fake.date_time_this_year(),
            "duration_ms": round(random.uniform(10.0, 1000.0), 1),
            "extra": {},
        }
        for _ in range(TAMANHOS["trace"])
    ]
