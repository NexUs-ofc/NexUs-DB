from dataclasses import dataclass

from .base import BaseEntity


@dataclass(kw_only=True)
class Profile(BaseEntity):
  address_id: int
  email: str
  name: str
  type: str
  status: str = "ACTIVE"
  profile_image_url: str | None = None


@dataclass(kw_only=True)
class ProfilePhone(BaseEntity):
  profile_id: int
  phone: str


@dataclass(kw_only=True)
class AuthMethod(BaseEntity):
  profile_id: int
  provider: str
  credential: str
