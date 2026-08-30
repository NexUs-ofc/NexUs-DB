from ..factories import home

DROP_ALLOWED = {
    "MONGO_metrics",
    "MONGO_records",
    "MONGO_tool_metrics",
    "MONGO_traces",
}

COLLECTIONS = {
    "MONGO_recipes": home.build_recipes,
    "MONGO_events": home.build_events,
    "MONGO_recipe_accounts": home.build_recipe_accounts,
    "MONGO_conversations": home.build_conversations,
    "MONGO_knowledge": home.build_knowledge,
    "MONGO_records": home.build_records,
    "MONGO_shopping_lists": home.build_shopping_lists,
    "MONGO_metrics": home.build_metrics,
    "MONGO_tool_metrics": home.build_tool_metrics,
    "MONGO_traces": home.build_traces,
}


def run(mongo):
    for name, builder in COLLECTIONS.items():
        if name in DROP_ALLOWED:
            mongo.drop_collection(name)
        mongo.bulk_insert(name, builder())
