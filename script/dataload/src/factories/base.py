from collections.abc import Iterable

from ..core.schemas.base import BaseEntity


def to_dicts(objects: Iterable[BaseEntity]) -> list[dict]:
    return [o.to_dict() for o in objects]
