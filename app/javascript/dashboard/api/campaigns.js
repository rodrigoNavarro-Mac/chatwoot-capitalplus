/* global axios */

import ApiClient from './ApiClient';

class CampaignsAPI extends ApiClient {
  constructor() {
    super('campaigns', { accountScoped: true });
  }

  attachCsv(campaignId, csvFile) {
    const formData = new FormData();
    formData.append('campaign[csv_audience]', csvFile);
    return axios.patch(`${this.url}/${campaignId}`, formData);
  }

  previewCsv(csvFile) {
    const formData = new FormData();
    formData.append('csv_audience', csvFile);
    return axios.post(`${this.url}/csv_preview`, formData);
  }

  metrics(campaignId) {
    return axios.get(`${this.url}/${campaignId}/metrics`);
  }

  recipients(campaignId, params) {
    return axios.get(`${this.url}/${campaignId}/recipients`, { params });
  }

  exportRecipients(campaignId, params) {
    return axios.get(`${this.url}/${campaignId}/recipients.csv`, { params });
  }

  pause(campaignId) {
    return axios.post(`${this.url}/${campaignId}/pause`);
  }

  resume(campaignId) {
    return axios.post(`${this.url}/${campaignId}/resume`);
  }

  analyticsMetrics(id) {
    return axios.get(`${this.url}/${id}/analytics/metrics`);
  }

  analyticsContacts(id, { status, page } = {}) {
    return axios.get(`${this.url}/${id}/analytics/contacts`, {
      params: { status, page },
    });
  }
}

export default new CampaignsAPI();
