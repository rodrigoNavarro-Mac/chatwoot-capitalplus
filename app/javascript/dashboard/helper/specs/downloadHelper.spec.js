import { generateFileName, downloadCsvFile } from '../downloadHelper';

describe('#generateFileName', () => {
  it('should generate the correct file name', () => {
    expect(generateFileName({ type: 'csat', to: 1652812199 })).toEqual(
      'csat-report-17-05-2022.csv'
    );

    expect(
      generateFileName({ type: 'csat', to: 1652812199, businessHours: true })
    ).toEqual('csat-report-17-05-2022-business-hours.csv');
  });
});

// El navegador decodifica la respuesta de axios como texto UTF-8 y, al hacerlo, se traga
// cualquier BOM que el servidor haya mandado -- así que el BOM tiene que agregarse aquí, del lado
// del cliente, o Excel en Windows corrompe acentos/ñ (bug real confirmado en producción).
describe('#downloadCsvFile', () => {
  const captureBlob = () => {
    let capturedBlob;
    global.URL.createObjectURL = vi.fn(blob => {
      capturedBlob = blob;
      return 'blob:mock-url';
    });
    return () => capturedBlob;
  };

  // Leemos los BYTES crudos (no vía FileReader#readAsText/Blob#text, que por diseño se tragan un
  // BOM inicial al decodificar -- justo el comportamiento que este fix busca evitar en el archivo
  // final. El anchor de descarga guarda los bytes del Blob tal cual, sin pasar por ese decode.
  const readBlobAsBytes = blob =>
    new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(new Uint8Array(reader.result));
      reader.onerror = reject;
      reader.readAsArrayBuffer(blob);
    });
  const BOM_BYTES = [0xef, 0xbb, 0xbf];

  it('prepends a UTF-8 BOM to the CSV content', async () => {
    const getBlob = captureBlob();

    downloadCsvFile('leads.csv', 'a,b\nAcentó,ñ\n');

    const bytes = await readBlobAsBytes(getBlob());
    expect(Array.from(bytes.slice(0, 3))).toEqual(BOM_BYTES);
  });

  it('does not duplicate the BOM when the content already starts with one', async () => {
    const getBlob = captureBlob();

    downloadCsvFile('leads.csv', '﻿a,b\n');

    const bytes = await readBlobAsBytes(getBlob());
    // 3 bytes de BOM + "a,b\n" (4 bytes ASCII) = 7 -- si el BOM se hubiera duplicado, serían 10.
    expect(bytes.length).toBe(7);
    expect(Array.from(bytes.slice(0, 3))).toEqual(BOM_BYTES);
  });
});
