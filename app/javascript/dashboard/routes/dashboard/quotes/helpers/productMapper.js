// Intenta mapear los campos custom conocidos del módulo Products de Zoho CRM (superficie, precio
// m2, desarrollo, color) a los campos del formulario de cotización. Los nombres exactos de estos
// campos custom no están confirmados contra la cuenta real de Zoho de este negocio -- si no
// coinciden, el campo queda vacío y el usuario lo captura a mano (el formulario es editable de
// cualquier forma, así que un mapeo incompleto no bloquea generar la cotización).
export function mapZohoProductToFields(product) {
  return {
    lote: product.Product_Name || '',
    desarrollo: product.Desarrollo || product.Desarollo || '',
    color: product.Color || '',
    superficie: product.Superficie ?? '',
    precio_m2: product.Precio_por_m2 ?? '',
  };
}

export function productLabel(product) {
  return product.Product_Name || product.id;
}
