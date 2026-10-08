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

  // CSV con todos los leads/deals de Zoho del periodo exacto de este reporte (data mart local de
  // Revenue Intelligence) -- para auditar fila por fila cuando el número mostrado se cuestiona.
  // Sin responseType: 'blob' -- downloadCsvFile (ver downloadHelper.js) espera el CSV como string
  // para poder revisar/forzar el BOM, mismo patrón que RevenueIntelligenceReport.vue#downloadLeadsExport.
  downloadLeadsExport(inboxId, id) {
    return axios.get(
      `${this.url}/${inboxId}/weekly_ops_reports/${id}/leads_export`
    );
  }

  // Sección "Auditoría" visible en pantalla (tabla paginada) -- a diferencia de
  // downloadLeadsExport (el CSV completo para descargar), esto es lo que se ve sin salir de la
  // página. Mismo builder/data mart del lado del servidor, ver controller#leads_audit.
  getLeadsAudit(inboxId, id, page = 1) {
    return axios.get(
      `${this.url}/${inboxId}/weekly_ops_reports/${id}/leads_audit`,
      { params: { page } }
    );
  }

  // Leads de este periodo sin ningún seguimiento humano (ni llamada, ni WhatsApp, ni marcado
  // "Contactado"/descartado en Zoho) -- mismo signal_type 'lead_no_contact' que ya usa Revenue
  // Intelligence (RevenueIntelligence::DetectRisksJob), acotado al inbox/periodo de este reporte.
  getNoContactLeads(inboxId, id, page = 1) {
    return axios.get(
      `${this.url}/${inboxId}/weekly_ops_reports/${id}/no_contact_leads`,
      { params: { page } }
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
