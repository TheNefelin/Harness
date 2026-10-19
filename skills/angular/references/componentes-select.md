# Select, selected-list y resolución de modelos

> Detalle de la subsección **Select components, selected-list y resolución de modelos** de la skill `angular`.

**Select component** (`{feature}-select-component/`):
- Emite el modelo completo via `selectedItem = output<FeatureModel | null>()` (el item seleccionado, `null` al limpiar).
- Contiene su propio `rxResource` para cargar la lista de opciones (`getAll()`).
- Expone `clearTrigger = input<number>(0)` para resetear la selección visual desde el padre.
- Expone `selectedId = input<number | undefined>(undefined)` (sin default numérico) para preseleccionar desde el padre.
- Emitir el modelo completo evita que el consumidor haga un segundo fetch del catálogo para resolver id → modelo.

**Selected-list component** (`{feature}-selected-list-component/`):
- Recibe la lista de items seleccionados como `input<FeatureModel[]>([])` (con default vacío).
- Emite `delete = output<FeatureModel>()` (sin prefijo `on`).
- El handler interno `handleDelete` hace `event.preventDefault()` + `event.stopPropagation()` antes de emitir.

**Consumo del modelo en el consumidor** (`book-form-component`, `edition-form-components`):
- El select emite el `FeatureModel` completo; el consumidor lo agrega directamente a su lista de seleccionados (sin re-fetch):

```ts
// book-form-component: recibe el AuthorModel completo del select
protected addAuthor(item: AuthorModel | null): void {
  if (!item) return;
  this.formData.update(data => ({
    ...data,
    authors: [...(data.authors ?? []), item]
  }));
}
```

- El `delete` del selected-list delega al page (`onDeleteAuthor`/`onDeleteSubject`) que solo persiste en modo edición (`isEditMode()`). En creación solo actualiza `formData` local (no hay filas puente en BD aún).
