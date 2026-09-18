/* global axios */
import ApiClient from './ApiClient';

class ZohoCrmOAuthClient extends ApiClient {
  constructor() {
    super('zoho_crm', { accountScoped: true });
  }

  generateAuthorization({ clientId, clientSecret, datacenter }) {
    return axios.post(`${this.url}/authorization`, {
      client_id: clientId,
      client_secret: clientSecret,
      datacenter,
    });
  }
}

export default new ZohoCrmOAuthClient();
