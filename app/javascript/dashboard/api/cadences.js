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

  analyticsVariants(params = {}) {
    return axios.get(`${this.baseUrl()}/cadences/analytics/variants`, {
      params,
    });
  }

  getCadenceDefinitions(inboxId) {
    return axios.get(`${this.baseUrl()}/cadences/definitions`, {
      params: { inbox_id: inboxId },
    });
  }

  createCadenceDefinition(inboxId, payload) {
    return axios.post(`${this.baseUrl()}/cadences/definitions`, {
      inbox_id: inboxId,
      ...payload,
    });
  }

  updateCadenceDefinition(id, payload) {
    return axios.patch(`${this.baseUrl()}/cadences/definitions/${id}`, payload);
  }

  deleteCadenceDefinition(id) {
    return axios.delete(`${this.baseUrl()}/cadences/definitions/${id}`);
  }

  getStepDefinitions(cadenceDefinitionId) {
    return axios.get(`${this.baseUrl()}/cadences/step_definitions`, {
      params: { cadence_definition_id: cadenceDefinitionId },
    });
  }

  createStepDefinition(cadenceDefinitionId, payload) {
    return axios.post(`${this.baseUrl()}/cadences/step_definitions`, {
      cadence_definition_id: cadenceDefinitionId,
      ...payload,
    });
  }

  updateStepDefinition(cadenceDefinitionId, id, payload) {
    return axios.patch(`${this.baseUrl()}/cadences/step_definitions/${id}`, {
      cadence_definition_id: cadenceDefinitionId,
      ...payload,
    });
  }

  deleteStepDefinition(cadenceDefinitionId, id) {
    return axios.delete(`${this.baseUrl()}/cadences/step_definitions/${id}`, {
      params: { cadence_definition_id: cadenceDefinitionId },
    });
  }

  reorderStepDefinitions(cadenceDefinitionId, orderedIds) {
    return axios.patch(`${this.baseUrl()}/cadences/step_definitions/reorder`, {
      cadence_definition_id: cadenceDefinitionId,
      ordered_ids: orderedIds,
    });
  }
}

export default new CadencesAPI();
