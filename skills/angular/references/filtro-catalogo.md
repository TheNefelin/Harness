# Listado paginado con filtro por catálogo

> Detalle de la subsección **Listado paginado con filtro por catálogo** de la skill `angular`. Aplica a listados con filtro por estado/catálogo (reservation, loan y sus status).

- **`getPaginationPayload` privado por página** (computed tipado con el `*FilterModel`). No se hace `override` de `getAllPayload` de `CrudPage`: es `PaginationRequestModel<null>` y por la varianza de `Signal<PaginationRequestModel<...>>` (TS2416) un `computed<...<LoanFilterModel>>` no es asignable a `computed<...<null>>`.
- **El select del catálogo emite el modelo completo** y el page recibe el item en el handler:
  `onFilterByIdStatus(status: FeatureStatusModel | null)` → `selectFilterStatusId.set(status?.id_status ?? 0)` + `currentPage.set(1)`.
- **Sentinel `0 = todos`**: `selectFilterStatusId = signal<number>(0)`; `ApiService.buildQuery` omite números `<= 0`, así que `0` = sin filtro.
- **Stream puro del rxResource de listado**:
  ```
  if (!params) return of(null);
  return this.featureService.getAllPagination(params).pipe(
    map(response => this.mapPaginated(response)),
    catchError(err => { console.error('[Service::Page] getAllPagination:', err); return of(this.emptyPaginated()); }),
  );
  ```
  Los side-effects de `totalPages` viven solo en `mapPaginated`/`emptyPaginated`.
- **El list component es presentacional y reemite el filtro**: `selectedIdStatus = output<FeatureStatusModel | null>()`; el template hace `<app-x-status-select-component [selectedId]="selectStatusId()" (selectedItem)="selectedIdStatus.emit($event)" />`.
