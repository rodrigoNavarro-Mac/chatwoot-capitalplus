import { frontendURL } from 'dashboard/helper/URLHelper.js';
import QuotesListPage from './pages/QuotesListPage.vue';
import QuoteDetailPage from './pages/QuoteDetailPage.vue';

const meta = {
  permissions: ['administrator', 'agent'],
};

const quotesRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/quotes'),
      name: 'quotes_dashboard_index',
      meta,
      component: QuotesListPage,
    },
    {
      path: frontendURL('accounts/:accountId/quotes/:quoteId'),
      name: 'quotes_dashboard_show',
      meta,
      component: QuoteDetailPage,
    },
  ],
};

export default quotesRoutes;
