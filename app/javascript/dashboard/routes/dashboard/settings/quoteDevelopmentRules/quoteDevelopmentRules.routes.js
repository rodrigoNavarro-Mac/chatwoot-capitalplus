import { frontendURL } from 'dashboard/helper/URLHelper';

import SettingsWrapper from '../SettingsWrapper.vue';
import QuoteDevelopmentRulesHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/quote-development-rules'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: 'list',
        },
        {
          path: 'list',
          name: 'quote_development_rules_list',
          meta: {
            permissions: ['administrator'],
          },
          component: QuoteDevelopmentRulesHome,
        },
      ],
    },
  ],
};
