/* global axios */
import ApiClient from './ApiClient';

class WeeklyOpsReportsAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  getReports(inboxId) {
    return axios.get(`${this.url}/${inboxId}/weekly_ops_reports`);
  }

  getReport(inboxId, id) {
    return axios.get(`${this.url}/${inboxId}/weekly_ops_reports/${id}`);
  }

  generateReport(inboxId, { since, until, periodType }) {
    return axios.post(`${this.url}/${inboxId}/weekly_ops_reports`, {
      since,
      until,
      period_type: periodType,
    });
  }

  downloadPdf(inboxId, id, chartImages = []) {
    return axios.post(
      `${this.url}/${inboxId}/weekly_ops_reports/${id}/pdf`,
      { chart_images: chartImages },
      { responseType: 'blob' }
    );
  }

  getBranding(inboxId) {
    return axios.get(`${this.url}/${inboxId}/report_branding`);
  }

  updateBranding(inboxId, formData) {
    return axios.patch(`${this.url}/${inboxId}/report_branding`, formData, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }
}

export default new WeeklyOpsReportsAPI();
