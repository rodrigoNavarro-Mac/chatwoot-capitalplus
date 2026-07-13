/* global axios */
import ApiClient from './ApiClient';

class CadencesAPI extends ApiClient {
  constructor() {
    super('cadence_enrollments', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  pause(id) {
    return axios.post(`${this.url}/${id}/pause`);
  }

  resume(id) {
    return axios.post(`${this.url}/${id}/resume`);
  }

  cancel(id) {
    return axios.post(`${this.url}/${id}/cancel`);
  }

  callTasks(params = {}) {
    return axios.get(`${this.baseUrl()}/cadence_call_tasks`, { params });
  }

  completeCallTask(id) {
    return axios.post(`${this.baseUrl()}/cadence_call_tasks/${id}/complete`);
  }

  analyticsSummary(params = {}) {
    return axios.get(`${this.baseUrl()}/cadences/analytics/summary`, {
      params,
    });
  }

  analyticsSteps(params = {}) {
    return axios.get(`${this.baseUrl()}/cadences/analytics/steps`, { params });
  }

  analyticsAgents(params = {}) {
    return axios.get(`${this.baseUrl()}/cadences/analytics/agents`, { params });
  }

  analyticsTemplates(params = {}) {
    return axios.get(`${this.baseUrl()}/cadences/analytics/templates`, {
      params,
    });
  }

  getTemplateMappings(inboxId) {
    return axios.get(`${this.baseUrl()}/cadences/template_mappings`, {
      params: { inbox_id: inboxId },
    });
  }

  updateTemplateMappings(inboxId, mappings) {
    return axios.patch(
      `${this.baseUrl()}/cadences/template_mappings/bulk_update`,
      { inbox_id: inboxId, mappings }
    );
  }

  resetTemplateMapping(inboxId, templateKey) {
    return axios.delete(
      `${this.baseUrl()}/cadences/template_mappings/${templateKey}`,
      { params: { inbox_id: inboxId } }
    );
  }
}

export default new CadencesAPI();
