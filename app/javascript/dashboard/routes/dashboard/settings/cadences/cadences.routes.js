import { frontendURL } from '../../../../helper/URLHelper';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/cadences'),
      name: 'cadence_analytics',
      meta: {
        permissions: ['administrator'],
        featureFlag: FEATURE_FLAGS.WHATSAPP_CADENCES,
      },
      component: Index,
    },
  ],
};
