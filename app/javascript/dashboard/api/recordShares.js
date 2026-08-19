/* global axios */
import ApiClient from './ApiClient';

class RecordShares extends ApiClient {
  constructor() {
    super('record_shares', { accountScoped: true });
  }

  get(shareableType, shareableId) {
    return axios.get(this.url, {
      params: { shareable_type: shareableType, shareable_id: shareableId },
    });
  }

  create({
    shareableType,
    shareableId,
    sharedWithType,
    sharedWithId,
    accessLevel = 'view',
  }) {
    return axios.post(this.url, {
      shareable_type: shareableType,
      shareable_id: shareableId,
      record_share: {
        shared_with_type: sharedWithType,
        shared_with_id: sharedWithId,
        access_level: accessLevel,
      },
    });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export default new RecordShares();
