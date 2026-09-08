/* global axios */
import ApiClient from './ApiClient';

// Acciones de escritura para la pestaña "Calidad de datos" de Revenue Intelligence — separado de
// ReportsAPI (que solo lee) a propósito, ver Api::V2::Accounts::RevenueIntelligenceController.
class RevenueIntelligenceAPI extends ApiClient {
  constructor() {
    super('revenue_intelligence', { accountScoped: true, apiVersion: 'v2' });
  }

  resolveIdentityConflict(id) {
    return axios.patch(`${this.url}/identity_conflicts/${id}/resolve`);
  }

  relinkDeal(id) {
    return axios.post(`${this.url}/deals/${id}/relink_lead`);
  }
}

export default new RevenueIntelligenceAPI();
