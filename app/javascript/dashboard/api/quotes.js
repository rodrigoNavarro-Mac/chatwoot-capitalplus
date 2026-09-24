/* global axios */

import ApiClient from './ApiClient';

class QuotesAPI extends ApiClient {
  constructor() {
    super('quotes', { accountScoped: true });
  }

  downloadPdf(id) {
    return axios.get(`${this.url}/${id}/pdf`, { responseType: 'blob' });
  }

  downloadAmortizationPdf(id) {
    return axios.get(`${this.url}/${id}/amortization_pdf`, {
      responseType: 'blob',
    });
  }

  getDevelopments() {
    return axios.get(`${this.url}/developments`);
  }

  searchProducts({ desarrollo, q } = {}) {
    return axios.get(`${this.url}/products`, { params: { desarrollo, q } });
  }
}

export default new QuotesAPI();
