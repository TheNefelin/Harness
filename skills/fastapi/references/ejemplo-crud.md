# Ejemplo CRUD completo (route → service → repository)

Patrón de referencia con una feature `products` (y `categories` como relación FK). Copialo como base de cada feature CRUD. Las reglas de cada capa están en el `SKILL.md`; acá va el código completo.

## Route (decide HTTP)

```python
# src/api/products/routes.py
from typing import Annotated
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.status import HTTP_200_OK, HTTP_201_CREATED, HTTP_204_NO_CONTENT

from src.core.dependencies import verify_api_key, require_admin
from src.core.database import get_db
from src.schemas import dtos
from . import service

router = APIRouter(prefix="/products", tags=["products"], dependencies=[Depends(verify_api_key)])


@router.get("/", response_model=dtos.PaginationResponse[dtos.ProductResponse], status_code=HTTP_200_OK,
            summary="List products", description="Paginated list, optionally filtered by category_id.")
async def get_products(
  params: Annotated[dtos.PaginationRequest, Depends()],
  category_id: int | None = None,
  db: AsyncSession = Depends(get_db),
):
  return await service.get_all(db, params.page, params.limit, category_id, params.search)


@router.get("/{id}", response_model=dtos.ProductResponse, status_code=HTTP_200_OK,
            summary="Get product by ID", description="Returns a product. 404 if not found.")
async def get_product(id: int, db: AsyncSession = Depends(get_db)):
  return await service.get_by_id(db, id)


@router.post("/", response_model=dtos.ProductResponse, status_code=HTTP_201_CREATED,
             summary="Create product")
async def create_product(data: dtos.ProductRequest, db: AsyncSession = Depends(get_db), _: dict = Depends(require_admin)):
  return await service.create(db, data)


@router.put("/{id}", response_model=dtos.ProductResponse, status_code=HTTP_200_OK,
            summary="Update product")
async def update_product(id: int, data: dtos.ProductRequest, db: AsyncSession = Depends(get_db), _: dict = Depends(require_admin)):
  return await service.update(db, id, data)


@router.delete("/{id}", status_code=HTTP_204_NO_CONTENT, summary="Delete product")
async def delete_product(id: int, db: AsyncSession = Depends(get_db), _: dict = Depends(require_admin)):
  await service.delete(db, id)
```

## Service (orquesta y aplica reglas de negocio)

```python
# src/api/products/service.py
from sqlalchemy.ext.asyncio import AsyncSession

from src.schemas import dtos
from src.core.exceptions import DuplicateNameError, NotFoundError
from . import repository


async def ensure_product_exists(db: AsyncSession, product_id: int) -> None:
  if not await repository.exists_by_id(db, product_id):
    raise NotFoundError("Product")


async def get_all(db: AsyncSession, page: int = 1, limit: int = 20, category_id: int | None = None, search: str | None = None) -> dtos.PaginationResponse[dtos.ProductResponse]:
  total = await repository.count(db, category_id, search)
  items = [dtos.ProductResponse.model_validate(e) for e in await repository.get_all(db, page, limit, category_id, search)]
  return dtos.PaginationResponse(page=page, limit=limit, total=total, items=items)


async def get_by_id(db: AsyncSession, id: int) -> dtos.ProductResponse:
  entity = await repository.get_by_id(db, id)
  if not entity:
    raise NotFoundError("Product")
  return dtos.ProductResponse.model_validate(entity)


async def create(db: AsyncSession, data: dtos.ProductRequest) -> dtos.ProductResponse:
  if await repository.exists_by_name(db, data.name):
    raise DuplicateNameError(data.name)
  return dtos.ProductResponse.model_validate(await repository.create(db, data.model_dump()))


async def update(db: AsyncSession, id: int, data: dtos.ProductRequest) -> dtos.ProductResponse:
  current = await repository.get_by_id(db, id)
  if not current:
    raise NotFoundError("Product")
  if data.name != current.name and await repository.exists_by_name(db, data.name):
    raise DuplicateNameError(data.name)
  return dtos.ProductResponse.model_validate(await repository.update(db, current, data.model_dump()))


async def delete(db: AsyncSession, id: int) -> None:
  entity = await repository.get_by_id(db, id)
  if not entity:
    raise NotFoundError("Product")
  await repository.delete(db, entity)
```

## Repository (solo queries SQLAlchemy)

```python
# src/api/products/repository.py
from sqlalchemy import select, exists, func
from sqlalchemy.ext.asyncio import AsyncSession

from src.models import models


async def count(db: AsyncSession, category_id: int | None = None, search: str | None = None) -> int:
  stmt = select(func.count(models.Product.id))
  if category_id is not None:
    stmt = stmt.where(models.Product.category_id == category_id)
  if search:
    stmt = stmt.where(models.Product.name.ilike(f"%{search}%"))
  return (await db.execute(stmt)).scalar_one()


async def get_all(db: AsyncSession, page: int = 1, limit: int = 20, category_id: int | None = None, search: str | None = None) -> list[models.Product]:
  stmt = select(models.Product)
  if category_id is not None:
    stmt = stmt.where(models.Product.category_id == category_id)
  if search:
    stmt = stmt.where(models.Product.name.ilike(f"%{search}%"))
  result = await db.execute(stmt.order_by(models.Product.name).offset((page - 1) * limit).limit(limit))
  return list(result.scalars().all())


async def exists_by_name(db: AsyncSession, name: str) -> bool:
  result = await db.execute(select(exists().where(models.Product.name == name)))
  return result.scalar_one()


async def exists_by_id(db: AsyncSession, id: int) -> bool:
  result = await db.execute(select(exists().where(models.Product.id == id)))
  return result.scalar_one()


async def get_by_id(db: AsyncSession, id: int) -> models.Product | None:
  result = await db.execute(select(models.Product).where(models.Product.id == id))
  return result.scalar_one_or_none()


async def create(db: AsyncSession, data: dict) -> models.Product:
  item = models.Product(**data)
  db.add(item)
  await db.commit()
  await db.refresh(item)
  return item


async def update(db: AsyncSession, item: models.Product, data: dict) -> models.Product:
  for key, value in data.items():
    setattr(item, key, value)
  await db.commit()
  await db.refresh(item)
  return item


async def delete(db: AsyncSession, item: models.Product) -> None:
  await db.delete(item)
  await db.commit()
```
