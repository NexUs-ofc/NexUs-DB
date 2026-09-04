from ..config import TAMANHOS
from ..factories import account, address, billing, catalog, pantry
from ..factories.base import to_dicts
from ..seed import get_all_fixed


def run(pg):
    fixed = get_all_fixed()
    pg.bulk_insert("category", fixed["category"])
    pg.bulk_insert("plan", fixed["plan"])

    pg.bulk_insert("address", to_dicts(address.build_addresses()))
    pg.bulk_insert("food", to_dicts(catalog.build_food()))

    pg.bulk_insert("profile", to_dicts(account.build_profiles()))

    pg.bulk_insert("profile_phone", to_dicts(account.build_profile_phones()))
    pg.bulk_insert("auth_method", to_dicts(account.build_auth_methods()))

    pg.bulk_insert("company", to_dicts(billing.build_companies()))
    pg.bulk_insert("store", to_dicts(billing.build_stores()))
    pg.bulk_insert("payment", to_dicts(billing.build_payments()))

    pg.bulk_insert("pantry_item", to_dicts(pantry.build_pantry_items()))
    pg.bulk_insert("pantry_product_setting",to_dicts(pantry.build_pantry_product_setting(TAMANHOS["food"])),)
