from ..core.mongo_ids import regenerate_mongo_ids
from ..factories import home

LEGACY_COLLECTION_PREFIX = "MONGO_"

DROP_ALLOWED = {
    "metrics",
    "records",
    "tool_metrics",
    "traces",
}

COLLECTIONS = {
    "recipes": home.build_recipes,
    "events": home.build_events,
    "recipe_accounts": home.build_recipe_accounts,
    "conversations": home.build_conversations,
    "knowledge": home.build_knowledge,
    "records": home.build_records,
    "shopping_lists": home.build_shopping_lists,
    "metrics": home.build_metrics,
    "tool_metrics": home.build_tool_metrics,
    "traces": home.build_traces,
}


def run(mongo, *, reset: bool = False):
    regenerate_mongo_ids()

    if reset:
        for name in DROP_ALLOWED:
            mongo.drop_collection(f"{LEGACY_COLLECTION_PREFIX}{name}")

    for name, builder in COLLECTIONS.items():
        documents = builder()

        if name in DROP_ALLOWED:
            mongo.drop_collection(name)

        mongo.bulk_insert(name, documents)
