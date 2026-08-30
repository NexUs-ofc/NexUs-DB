from .base import BaseEntity
from typing import Optional
from datetime import date, datetime
from dataclasses import dataclass

@dataclass(kw_only=True)
class Plan(BaseEntity):
  plan_name: str
  plan_price: float
  store_limit: int
  is_active: bool = True
  description: Optional[str] = None
  updated_at: Optional[datetime] = None


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
  paid_at: Optional[datetime] = None
  updated_at: Optional[datetime] = None
