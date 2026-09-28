import ApiClient from './ApiClient';

class QuoteDevelopmentRulesAPI extends ApiClient {
  constructor() {
    super('quote_development_rules', { accountScoped: true });
  }
}

export default new QuoteDevelopmentRulesAPI();
