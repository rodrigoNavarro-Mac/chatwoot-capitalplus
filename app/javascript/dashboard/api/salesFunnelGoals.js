/* global axios */

import ApiClient from './ApiClient';

class SalesFunnelGoals extends ApiClient {
  constructor() {
    super('sales_funnel_goals', { accountScoped: true });
  }

  get({ developmentKey, periodMonth } = {}) {
    return axios.get(this.url, {
      params: { development_key: developmentKey, period_month: periodMonth },
    });
  }
}

export default new SalesFunnelGoals();
