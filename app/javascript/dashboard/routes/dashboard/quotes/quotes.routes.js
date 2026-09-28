import { frontendURL } from 'dashboard/helper/URLHelper.js';
import QuotesListPage from './pages/QuotesListPage.vue';
import QuoteDetailPage from './pages/QuoteDetailPage.vue';

// 'custom_role' es necesario además de 'administrator'/'agent': un account_user con un rol
// personalizado asignado expone SOLO los permisos de ese rol (+ el marcador 'custom_role') en
// vez de la palabra "agent" (ver Enterprise::AccountUser#permissions) — sin este valor aquí,
// cualquier agente con un rol personalizado queda bloqueado del módulo aunque el rol no
// restrinja nada de Cotizaciones explícitamente.
const meta = {
  permissions: ['administrator', 'agent', 'custom_role'],
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
