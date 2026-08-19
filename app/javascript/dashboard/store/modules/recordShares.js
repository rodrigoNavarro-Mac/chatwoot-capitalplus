import RecordSharesAPI from '../../api/recordShares';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const keyFor = (shareableType, shareableId) =>
  `${shareableType}_${shareableId}`;

export const state = {
  recordsByKey: {},
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isDeleting: false,
  },
};

export const getters = {
  getShares: $state => (shareableType, shareableId) =>
    $state.recordsByKey[keyFor(shareableType, shareableId)] || [],
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  fetch: async ({ commit }, { shareableType, shareableId }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await RecordSharesAPI.get(shareableType, shareableId);
      commit('SET_SHARES', {
        shareableType,
        shareableId,
        shares: response.data,
      });
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  create: async ({ commit, dispatch }, payload) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      await RecordSharesAPI.create(payload);
      await dispatch('fetch', {
        shareableType: payload.shareableType,
        shareableId: payload.shareableId,
      });
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
    return null;
  },

  remove: async ({ commit, dispatch }, { id, shareableType, shareableId }) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await RecordSharesAPI.delete(id);
      await dispatch('fetch', { shareableType, shareableId });
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },
};

export const mutations = {
  SET_UI_FLAG(_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  SET_SHARES(_state, { shareableType, shareableId, shares }) {
    _state.recordsByKey = {
      ..._state.recordsByKey,
      [keyFor(shareableType, shareableId)]: shares,
    };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
