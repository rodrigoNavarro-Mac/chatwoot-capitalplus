import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';

// El navegador decodifica la respuesta de axios como texto UTF-8 y, al hacerlo, se traga
// cualquier BOM que el servidor haya mandado al inicio del CSV (es el comportamiento estándar de
// TextDecoder) -- agregar el BOM del lado del servidor no sobrevive ese paso. Sin el BOM aquí, del
// lado del cliente, Excel en Windows reinterpreta el archivo como Windows-1252 y corrompe
// acentos/ñ (confirmado en producción, 2026-09-17).
const UTF8_BOM = '﻿';

export const downloadCsvFile = (fileName, content) => {
  const contentType = 'data:text/csv;charset=utf-8;';
  const contentWithBom = content.startsWith(UTF8_BOM)
    ? content
    : `${UTF8_BOM}${content}`;
  const blob = new Blob([contentWithBom], { type: contentType });
  const url = URL.createObjectURL(blob);

  const link = document.createElement('a');
  link.setAttribute('download', fileName);
  link.setAttribute('href', url);
  link.click();
  return link;
};

export const downloadBlobFile = (fileName, blob) => {
  const url = URL.createObjectURL(blob);

  const link = document.createElement('a');
  link.setAttribute('download', fileName);
  link.setAttribute('href', url);
  link.click();
  URL.revokeObjectURL(url);
  return link;
};

export const generateFileName = ({ type, to, businessHours = false }) => {
  let name = `${type}-report-${format(fromUnixTime(to), 'dd-MM-yyyy')}`;
  if (businessHours) {
    name = `${name}-business-hours`;
  }
  return `${name}.csv`;
};
