export const AVAILABLE_CUSTOM_ROLE_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
  'contact_view',
  'contact_manage',
  'report_view',
  'report_manage',
  'knowledge_base_view',
  'knowledge_base_manage',
  'cadence_view',
  'cadence_manage',
  'sales_funnel_view',
  'sales_funnel_manage',
  'weekly_ops_report_view',
  'weekly_ops_report_manage',
  'campaign_view',
  'campaign_manage',
  'crm_view',
  'crm_manage',
];

// Matriz de módulos para la UI de Custom Roles: cada fila es un módulo con sus permisos
// "ver"/"administrar" (o, para conversaciones, su jerarquía especial de 3 niveles ya existente).
export const PERMISSION_MODULES = [
  {
    key: 'contact',
    viewPermission: 'contact_view',
    managePermission: 'contact_manage',
  },
  {
    key: 'report',
    viewPermission: 'report_view',
    managePermission: 'report_manage',
  },
  {
    key: 'knowledge_base',
    viewPermission: 'knowledge_base_view',
    managePermission: 'knowledge_base_manage',
  },
  {
    key: 'cadence',
    viewPermission: 'cadence_view',
    managePermission: 'cadence_manage',
  },
  {
    key: 'sales_funnel',
    viewPermission: 'sales_funnel_view',
    managePermission: 'sales_funnel_manage',
  },
  {
    key: 'weekly_ops_report',
    viewPermission: 'weekly_ops_report_view',
    managePermission: 'weekly_ops_report_manage',
  },
  {
    key: 'campaign',
    viewPermission: 'campaign_view',
    managePermission: 'campaign_manage',
  },
  { key: 'crm', viewPermission: 'crm_view', managePermission: 'crm_manage' },
];

export const ROLES = ['agent', 'administrator'];

export const CONVERSATION_PERMISSIONS = [
  'conversation_manage',
  'conversation_unassigned_manage',
  'conversation_participating_manage',
];

export const MANAGE_ALL_CONVERSATION_PERMISSIONS = 'conversation_manage';

export const CONVERSATION_UNASSIGNED_PERMISSIONS =
  'conversation_unassigned_manage';

export const CONVERSATION_PARTICIPATING_PERMISSIONS =
  'conversation_participating_manage';

export const CONTACT_PERMISSIONS = 'contact_manage';

export const REPORTS_PERMISSIONS = 'report_manage';

export const PORTAL_PERMISSIONS = 'knowledge_base_manage';

export const ASSIGNEE_TYPE_TAB_PERMISSIONS = {
  me: {
    count: 'mineCount',
    permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
  },
  unassigned: {
    count: 'unAssignedCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_UNASSIGNED_PERMISSIONS,
    ],
  },
  all: {
    count: 'allCount',
    permissions: [
      ...ROLES,
      MANAGE_ALL_CONVERSATION_PERMISSIONS,
      CONVERSATION_PARTICIPATING_PERMISSIONS,
    ],
  },
};
