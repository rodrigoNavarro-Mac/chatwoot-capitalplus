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

  syncNow() {
    return axios.post(`${this.url}/sync_now`);
  }

  // Captura manual de inversión de Meta Ads (tab Marketing) — ver RevenueAdSpend.
  getAdSpends() {
    return axios.get(`${this.url}/ad_spends`);
  }

  createAdSpend(adSpend, force = false) {
    return axios.post(`${this.url}/ad_spends`, { ad_spend: adSpend, force });
  }

  updateAdSpend(id, adSpend, force = false) {
    return axios.patch(`${this.url}/ad_spends/${id}`, {
      ad_spend: adSpend,
      force,
    });
  }

  deleteAdSpend(id) {
    return axios.delete(`${this.url}/ad_spends/${id}`);
  }
}

export default new RevenueIntelligenceAPI();
