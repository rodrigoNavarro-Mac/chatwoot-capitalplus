// Mapeo confirmado contra el esquema real del módulo Products de esta cuenta de Zoho CRM
// (2026-09-24): Product_Name = lote, Desarrollo = desarrollo (Pick List, sin el typo de una sola
// erre que sí tiene el campo homónimo en Deals), m2 = superficie, x_m2_estimado = precio por m².
// No existe un campo "Color" en Products (sí en Deals) — se deja en blanco para captura manual.
// Fecha_de_entrega sí existe en Products y se usa como default editable.
export function mapZohoProductToFields(product) {
  return {
    lote: product.Product_Name || '',
    desarrollo: product.Desarrollo || '',
    color: '',
    superficie: product.m2 ?? '',
    precio_m2: product.x_m2_estimado ?? '',
    fecha_entrega: product.Fecha_de_entrega || '',
  };
}

// "Apartado"/"Bloqueado" (Boolean) marcan un lote reservado/bloqueado — se muestra como
// advertencia visual en el resultado de búsqueda para que no se cotice por error un lote que ya
// no está disponible; no bloquea la selección porque puede haber excepciones de negocio.
export function productAvailabilityWarning(product) {
  if (product.Bloqueado) return 'BLOCKED';
  if (product.Apartado) return 'RESERVED';
  return null;
}

export function productLabel(product) {
  const parts = [product.Product_Name || product.id];
  if (product.Desarrollo) parts.push(product.Desarrollo);
  return parts.join(' · ');
}
