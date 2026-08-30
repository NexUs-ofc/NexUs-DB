import random
import re
from datetime import timedelta
from ..core.rng import get_faker
from ..core.schemas.billing import Plan, Company, Store, Payment
from ..core.ids import RANGES
from ..seed import PLANS as FIXED_PLANS
from ..config import TAMANHOS

fake = get_faker()


def build_plans() -> list[Plan]:
    return [
        Plan(
            plan_name=p["plan_name"],
            plan_price=p["plan_price"],
            store_limit=p["store_limit"],
            description=p["description"],
            is_active=p["is_active"],
        )
        for p in FIXED_PLANS
    ]


def build_companies() -> list[Company]:
    return [
        Company(
            plan_id=random.randint(1, len(FIXED_PLANS)),
            cnpj=re.sub(r'[./-]', '', fake.unique.cnpj()),
            profile_id=pid,
        )
        for pid in RANGES["company"]
    ]


def build_stores() -> list[Store]:
    n_companies = len(RANGES["company"])
    return [
        Store(
            cnpj=re.sub(r'[./-]', '', fake.unique.cnpj()),
            company_id=random.randint(1, n_companies),
            profile_id=pid,
        )
        for pid in RANGES["store"]
    ]


def build_payments() -> list[Payment]:
    result = []
    for _ in range(TAMANHOS["payment"]):
        start = fake.date_between(start_date="-90d", end_date="today")
        result.append(Payment(
            due_date=start + timedelta(days=30),
            billing_period_start=start,
            billing_period_end=start + timedelta(days=30),
            payment_status=fake.random_element(elements=['PENDING', 'PAID', 'OVERDUE', 'CANCELLED']),
            company_id=random.randint(1, len(RANGES["company"])),
            plan_id=random.randint(1, len(FIXED_PLANS)),
            amount=round(random.uniform(29.90, 499.90), 2),
        ))
    return result
