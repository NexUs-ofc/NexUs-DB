from dataclasses import dataclass
from datetime import date, datetime

from .base import BaseEntity


@dataclass(kw_only=True)
class Plan(BaseEntity):
  plan_name: str
  plan_price: float
  store_limit: int
  is_active: bool = True
  description: str | None = None
  updated_at: datetime | None = None


@dataclass(kw_only=True)
class Company(BaseEntity):
  plan_id: int
  cnpj: str
  profile_id: int


@dataclass(kw_only=True)
class Store(BaseEntity):
  cnpj: str
  company_id: int
  profile_id: int


@dataclass(kw_only=True)
class Payment(BaseEntity):
  due_date: date
  billing_period_start: date
  billing_period_end: date
  payment_status: str
  company_id: int
  plan_id: int
  amount: float
  paid_at: datetime | None = None
  updated_at: datetime | None = None
