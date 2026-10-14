# DTOs (Pydantic v2) — código

Las reglas están en el `SKILL.md`; acá va el código completo.

```python
# src/schemas/dtos.py
from datetime import datetime
from typing import Generic, TypeVar
from pydantic import BaseModel, ConfigDict, Field

T = TypeVar("T")


class AppModel(BaseModel):
  model_config = ConfigDict(from_attributes=True)


class PaginationRequest(BaseModel):
  page: int = Field(default=1, ge=1)
  limit: int = Field(default=20, ge=1, le=100)
  search: str | None = None


class PaginationResponse(BaseModel, Generic[T]):
  page: int
  limit: int
  total: int
  items: list[T]


class CategoryResponse(AppModel):
  id: int
  name: str


class ProductRequest(BaseModel):
  category_id: int = Field(ge=1)
  name: str = Field(min_length=1, max_length=100)
  slug: str = Field(min_length=1, max_length=100)
  price: int = Field(ge=0)
  is_enabled: bool = True


class ProductResponse(AppModel):
  id: int
  category_id: int
  name: str
  slug: str
  price: int
  is_enabled: bool
  created_at: datetime
  updated_at: datetime
```

## Detalle anidado (vista enriquecida)

Cuando un recurso expone una vista enriquecida: un `*DetailResponse` que hereda del Response base y agrega las listas anidadas. En el repository se carga con `selectinload` en cadena y en el service se valida con `model_validate`.

```python
class ProductDetailResponse(ProductResponse):
  category: CategoryResponse
  reviews: list["ReviewResponse"]
```

```python
# repository: carga eager en cadena (evita N+1)
result = await db.execute(
  select(models.Product)
  .options(
    joinedload(models.Product.category),
    selectinload(models.Product.reviews),
  )
  .where(models.Product.id == id)
)
entity = result.unique().scalar_one_or_none()
```
