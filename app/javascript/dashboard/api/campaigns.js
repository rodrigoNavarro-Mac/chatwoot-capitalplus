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
}

export default new CampaignsAPI();
