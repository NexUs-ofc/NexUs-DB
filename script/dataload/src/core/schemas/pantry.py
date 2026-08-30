from .base import BaseEntity
from typing import Optional
from datetime import date
from dataclasses import dataclass

@dataclass(kw_only=True)
class PantryItem(BaseEntity):
  food_id: int
  profile_id: int
  quantity: int
  expiry_date: Optional[date] = None


@dataclass(kw_only=True)
class PantryProductSetting(BaseEntity):
  food_id: int
  profile_id: int
  minimum_quantity: int = 0
  updated_at: Optional[str] = None
