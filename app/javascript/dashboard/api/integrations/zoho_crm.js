/* global axios */

import ApiClient from '../ApiClient';

class ZohoCrmAPI extends ApiClient {
  constructor() {
    super('integrations/zoho_crm', { accountScoped: true });
  }

  getContactData(contactId, conversationId) {
    return axios.get(`${this.url}/contact_data`, {
      params: { contact_id: contactId, conversation_id: conversationId },
    });
  }

  createLead(contactId, conversationId) {
    return axios.post(`${this.url}/create_lead`, {
      contact_id: contactId,
      conversation_id: conversationId,
    });
  }

  updateStage(contactId, stage) {
    return axios.patch(`${this.url}/update_stage`, {
      contact_id: contactId,
      stage,
    });
  }

  pushToCrm(contactId, conversationId) {
    return axios.post(`${this.url}/push_to_crm`, {
      contact_id: contactId,
      conversation_id: conversationId,
    });
  }

  createDeal(contactId, dealName, stage, closingDate) {
    return axios.post(`${this.url}/create_deal`, {
      contact_id: contactId,
      deal_name: dealName,
      stage,
      closing_date: closingDate,
    });
  }

  createCrmNote(contactId, content, title) {
    return axios.post(`${this.url}/create_crm_note`, {
      contact_id: contactId,
      content,
      title,
    });
  }

  syncDeals() {
    return axios.post(`${this.url}/sync_deals`);
  }
}

export default new ZohoCrmAPI();
