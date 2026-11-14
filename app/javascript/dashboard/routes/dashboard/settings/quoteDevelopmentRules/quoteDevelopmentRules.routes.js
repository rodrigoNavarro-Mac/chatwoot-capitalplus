import { frontendURL } from 'dashboard/helper/URLHelper';
import { QUOTE_SENSITIVE_FIELDS_PERMISSION } from 'dashboard/constants/permissions.js';

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
            permissions: ['administrator', QUOTE_SENSITIVE_FIELDS_PERMISSION],
          },
          component: QuoteDevelopmentRulesHome,
        },
      ],
    },
  ],
};
