# `CrudPage<TModel>` y estado agrupado

> Detalle de la subsección **Páginas de listado** de la skill `angular`.

```ts
// shared/base/crud-page.ts (esqueleto)
export abstract class CrudPage<TModel> {
  protected readonly totalPages = signal(0);
  protected readonly currentPage = signal(1);
  protected readonly limit = signal<number>(10);
  protected readonly search = signal('');

  protected readonly getAllPayload = computed(() => ({
    page: this.currentPage(),
    limit: this.limit(),
    search: this.search(),
  }));

  nextPage(): void { ... }
  prevPage(): void { ... }
  onFilterChange(filter: { search: string; limit: number }): void { ... }
  onRefreshClick(): void { ... }
  abstract reload(): void;
}
```

**Estado agrupado por feature** (objeto plano con signals/computed, nunca signals sueltas):

```ts
// patrón de estado agrupado en el page
protected readonly genre = {
  dataList:    computed<GenreModel[]>(() => this.getAllGenreRX.value() ?? []),
  isLoading:   computed<boolean>(() => this.getAllGenreRX.isLoading()),
  isSaving:    signal<boolean>(false),
  showModal:   signal<boolean>(false),
  selectedItem: signal<GenreModel | null>(null),
}
```
