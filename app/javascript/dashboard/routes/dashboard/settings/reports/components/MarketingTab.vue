<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RevenueIntelligenceAPI from 'dashboard/api/revenueIntelligence';
import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import FunnelStageMeter from './FunnelStageMeter.vue';
import MarketingSpendModal from './MarketingSpendModal.vue';

const props = defineProps({
  report: { type: Object, default: null },
  campaignId: { type: String, default: '' },
  adsetId: { type: String, default: '' },
  advertId: { type: String, default: '' },
});

const emit = defineEmits(['updateFilters']);

const { t } = useI18n();

const spendModalRef = ref(null);

// -- Filtros de campaña/adset/anuncio (sección 1 del brief) --------------------------------------
const filterOptions = computed(
  () => props.report?.marketing_filter_options ?? []
);
const campaignFilterOptions = computed(() => [
  {
    value: '',
    label: t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.FILTER_ALL_CAMPAIGNS'),
  },
  ...filterOptions.value.map(c => ({ value: c.id, label: c.id })),
]);
const selectedCampaign = computed(() =>
  filterOptions.value.find(c => c.id === props.campaignId)
);
const adsetFilterOptions = computed(() => [
  {
    value: '',
    label: t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.FILTER_ALL_ADSETS'),
  },
  ...(selectedCampaign.value?.adsets ?? []).map(a => ({
    value: a.id,
    label: a.name || a.id,
  })),
]);
const selectedAdset = computed(() =>
  (selectedCampaign.value?.adsets ?? []).find(a => a.id === props.adsetId)
);
const advertFilterOptions = computed(() => [
  {
    value: '',
    label: t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.FILTER_ALL_ADVERTS'),
  },
  ...(selectedAdset.value?.adverts ?? []).map(a => ({
    value: a.id,
    label: a.name || a.id,
  })),
]);

const onCampaignFilterChange = value => {
  emit('updateFilters', { campaignId: value, adsetId: '', advertId: '' });
};
const onAdsetFilterChange = value => {
  emit('updateFilters', {
    campaignId: props.campaignId,
    adsetId: value,
    advertId: '',
  });
};
const onAdvertFilterChange = value => {
  emit('updateFilters', {
    campaignId: props.campaignId,
    adsetId: props.adsetId,
    advertId: value,
  });
};

// -- Formato -------------------------------------------------------------------------------------
const currencyFormatter = new Intl.NumberFormat('es-MX', {
  style: 'currency',
  currency: 'MXN',
  maximumFractionDigits: 0,
});
const formatCurrency = value =>
  value === null || value === undefined
    ? t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.NA')
    : currencyFormatter.format(value);
const formatPercent = value =>
  value === null || value === undefined
    ? t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.NA')
    : `${(value * 100).toFixed(1)}%`;
const formatSeconds = seconds => {
  if (seconds === null || seconds === undefined)
    return t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.NA');
  const minutes = Math.floor(seconds / 60);
  const remaining = Math.round(seconds % 60);
  return minutes > 0 ? `${minutes}m ${remaining}s` : `${remaining}s`;
};

// -- Semáforo de objetivo (sección 9: "no colores arbitrarios") -----------------------------------
// min/max ausentes = sin límite de ese lado. NEAR_MARGIN = qué tan cerca del límite incumplido
// todavía se considera "cerca del objetivo" en vez de "fuera".
const NEAR_MARGIN = 0.2;
const targetStatus = (value, { min, max } = {}) => {
  if (value === null || value === undefined) return 'unknown';
  const belowMin = min !== undefined && value < min;
  const aboveMax = max !== undefined && value > max;
  if (!belowMin && !aboveMax) return 'on_target';
  if (belowMin && value >= min * (1 - NEAR_MARGIN)) return 'near_target';
  if (aboveMax && value <= max * (1 + NEAR_MARGIN)) return 'near_target';
  return 'off_target';
};
const STATUS_CLASSES = {
  on_target: 'text-n-teal-11',
  near_target: 'text-n-amber-11',
  off_target: 'text-n-ruby-11',
  unknown: 'text-n-slate-11',
};
const statusClass = status => STATUS_CLASSES[status] || STATUS_CLASSES.unknown;

// -- Funnel (sección 3) ----------------------------------------------------------------------------
const FUNNEL_LABELS = {
  lead_created: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_CREATED'),
  lead_contacted: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_CONTACTED'),
  lead_qualified: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_QUALIFIED'),
  appointment_created: t(
    'REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.APPOINTMENT_CREATED'
  ),
  visit_effective: t(
    'REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.VISIT_EFFECTIVE'
  ),
  closed_won: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.CLOSED_WON'),
};
// Mismo componente visual que Overview (FunnelStageMeter) y mismo criterio de actualPercent:
// conversión contra la etapa ANTERIOR, no contra el total de leads (conversion_from_previous, no
// conversion_from_leads) -- para lead_created (primera etapa, sin "anterior") se muestra 100%,
// igual que Overview con su `step.conversion ?? 1`. Íconos/angostamiento son EXACTAMENTE los
// mismos 6 valores que usa FUNNEL_STAGE_ICONS/FUNNEL_STAGE_TAPER de RevenueIntelligenceReport.vue
// -- el funnel de Marketing ahora cubre el mismo rango completo (Leads..Cerrado ganado).
const FUNNEL_STAGE_ICONS = {
  lead_created: 'i-lucide-users',
  lead_contacted: 'i-lucide-phone',
  lead_qualified: 'i-lucide-clipboard-check',
  appointment_created: 'i-lucide-calendar',
  visit_effective: 'i-lucide-map-pin',
  closed_won: 'i-lucide-trophy',
};
const FUNNEL_STAGE_TAPER = {
  lead_created: 100,
  lead_contacted: 92,
  lead_qualified: 84,
  appointment_created: 76,
  visit_effective: 68,
  closed_won: 64,
};
const funnelMeterSteps = computed(() =>
  (props.report?.marketing_funnel ?? []).map(step => ({
    stage: step.metric,
    icon: FUNNEL_STAGE_ICONS[step.metric],
    label: FUNNEL_LABELS[step.metric] || step.metric,
    count: step.count,
    taperPercent: FUNNEL_STAGE_TAPER[step.metric],
    actualPercent: Math.round((step.conversion_from_previous ?? 1) * 100),
    seguimientoCount: step.seguimiento_count,
    lostCount: step.lost_count,
  }))
);

// -- Totales / cards ejecutivas (sección 9) --------------------------------------------------------
const totals = computed(
  () =>
    props.report?.marketing_totals ?? {
      lead_created: 0,
      lead_contacted: 0,
      lead_qualified: 0,
      appointment_created: 0,
      visit_effective: 0,
      closed_won: 0,
    }
);
const spend = computed(
  () =>
    props.report?.marketing_spend ?? {
      total_amount: null,
      coverage: { ads_with_leads: 0, ads_with_spend: 0 },
      costs: {},
    }
);
const sla = computed(() => props.report?.marketing_sla ?? null);

function safeRate(numerator, denominator) {
  if (!denominator) return null;
  return numerator / denominator;
}

const contactRate = computed(() =>
  safeRate(totals.value.lead_contacted, totals.value.lead_created)
);
const qualificationRateLeads = computed(() =>
  safeRate(totals.value.lead_qualified, totals.value.lead_created)
);
const qualificationRateContacted = computed(() =>
  safeRate(totals.value.lead_qualified, totals.value.lead_contacted)
);
const appointmentRateLeads = computed(() =>
  safeRate(totals.value.appointment_created, totals.value.lead_created)
);
const appointmentRateQualified = computed(() =>
  safeRate(totals.value.appointment_created, totals.value.lead_qualified)
);
const showRate = computed(() =>
  safeRate(totals.value.visit_effective, totals.value.appointment_created)
);
const noShowRate = computed(() => {
  const rate = showRate.value;
  return rate === null ? null : 1 - rate;
});

// -- Filas jerárquicas "Por fuente" (comportamiento ya existente, sin cambios de lógica) -----------
const MARKETING_METRIC_COLUMNS = [
  'lead_created',
  'lead_contacted',
  'lead_qualified',
  'appointment_created',
  'visit_effective',
  'closed_won',
];
const hasMarketingActivity = metrics =>
  MARKETING_METRIC_COLUMNS.some(metric => (metrics?.[metric] || 0) > 0);
const expandedCampaigns = ref(new Set());
const toggleCampaign = key => {
  const next = new Set(expandedCampaigns.value);
  if (next.has(key)) next.delete(key);
  else next.add(key);
  expandedCampaigns.value = next;
};
const marketingRows = computed(() => {
  const sources = props.report?.marketing_by_source ?? [];
  const rows = [];
  sources.forEach(source => {
    rows.push({
      key: `s:${source.id}`,
      level: 0,
      label: source.id,
      metrics: source.metrics,
      withoutCampaign: hasMarketingActivity(source.direct_metrics)
        ? source.direct_metrics.lead_created || 0
        : 0,
    });
    (source.campaigns ?? []).forEach(campaign => {
      const campaignKey = `c:${source.id}:${campaign.id}`;
      const adsets = campaign.adsets ?? [];
      const isExpanded = expandedCampaigns.value.has(campaignKey);
      rows.push({
        key: campaignKey,
        level: 1,
        label: campaign.id,
        metrics: campaign.metrics,
        withoutCampaign: 0,
        expandable: adsets.length > 0,
        expanded: isExpanded,
      });
      if (adsets.length === 0 || !isExpanded) return;

      adsets.forEach(adset => {
        rows.push({
          key: `a:${campaign.id}:${adset.id}`,
          level: 2,
          label: adset.name,
          metrics: adset.metrics,
          withoutCampaign: 0,
        });
        (adset.adverts ?? []).forEach(advert => {
          rows.push({
            key: `d:${campaign.id}:${adset.id}:${advert.id}`,
            level: 3,
            label: advert.name,
            metrics: advert.metrics,
            withoutCampaign: 0,
          });
        });
      });
    });
  });
  return rows;
});

// -- Tabla de funnel + costo por anuncio (secciones 11/12), ordenable -------------------------------
const AD_TABLE_METRICS = [
  'lead_created',
  'lead_contacted',
  'lead_qualified',
  'appointment_created',
  'visit_effective',
];
const sortKey = ref('lead_created');
const sortDir = ref('desc');
const setSort = key => {
  if (sortKey.value === key) {
    sortDir.value = sortDir.value === 'desc' ? 'asc' : 'desc';
  } else {
    sortKey.value = key;
    sortDir.value = 'desc';
  }
};
const sortValue = (row, key) => {
  if (key === 'ad') return row.advert_name || '';
  if (key === 'spend_amount') return row.spend_amount ?? -1;
  if (AD_TABLE_METRICS.includes(key)) return row.metrics[key] || 0;
  return row.costs?.[key] ?? row.rates?.[key] ?? 0;
};
const adTable = computed(() => {
  const rows = [...(props.report?.marketing_ad_table ?? [])];
  const dir = sortDir.value === 'asc' ? 1 : -1;
  rows.sort((a, b) => {
    const av = sortValue(a, sortKey.value);
    const bv = sortValue(b, sortKey.value);
    if (av < bv) return -1 * dir;
    if (av > bv) return 1 * dir;
    return 0;
  });
  return rows;
});

// -- Administración de inversión capturada (sección 10.5) --------------------------------------------
const adSpends = ref([]);
const isLoadingSpends = ref(false);
const fetchAdSpends = async () => {
  isLoadingSpends.value = true;
  try {
    const response = await RevenueIntelligenceAPI.getAdSpends();
    adSpends.value = response.data;
  } catch (error) {
    // silencioso -- la lista de administración es secundaria, el resto del tab sigue funcionando
  } finally {
    isLoadingSpends.value = false;
  }
};
onMounted(fetchAdSpends);

const openNewSpend = () => spendModalRef.value?.open();
const openEditSpend = adSpend => spendModalRef.value?.open(adSpend);
const onSpendSaved = () => {
  fetchAdSpends();
  emit('updateFilters', {
    campaignId: props.campaignId,
    adsetId: props.adsetId,
    advertId: props.advertId,
    refetch: true,
  });
};
const deleteSpend = async adSpend => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.DELETE_CONFIRM')
    )
  )
    return;

  try {
    await RevenueIntelligenceAPI.deleteAdSpend(adSpend.id);
    useAlert(t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.DELETED'));
    onSpendSaved();
  } catch (error) {
    useAlert(t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <!-- Filtros de campaña / adset / anuncio -->
    <div class="flex flex-wrap items-end gap-3">
      <div>
        <label class="text-xs text-n-slate-11 mb-1 block">{{
          t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.FILTER_CAMPAIGN')
        }}</label>
        <Select
          :model-value="campaignId"
          :options="campaignFilterOptions"
          @update:model-value="onCampaignFilterChange"
        />
      </div>
      <div>
        <label class="text-xs text-n-slate-11 mb-1 block">{{
          t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.FILTER_ADSET')
        }}</label>
        <Select
          :model-value="adsetId"
          :options="adsetFilterOptions"
          :disabled="!campaignId"
          @update:model-value="onAdsetFilterChange"
        />
      </div>
      <div>
        <label class="text-xs text-n-slate-11 mb-1 block">{{
          t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.FILTER_ADVERT')
        }}</label>
        <Select
          :model-value="advertId"
          :options="advertFilterOptions"
          :disabled="!adsetId"
          @update:model-value="onAdvertFilterChange"
        />
      </div>
      <Button
        class="ml-auto"
        :label="t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_ADD_BUTTON')"
        size="sm"
        @click="openNewSpend"
      />
    </div>

    <!-- Cards ejecutivas -->
    <div
      class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
    >
      <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.TOTALS_TITLE') }}
      </h3>
      <div class="flex flex-wrap gap-6">
        <div class="min-w-[8rem]">
          <h4 class="m-0 text-sm font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_TOTAL') }}
          </h4>
          <p class="mt-1 mb-0 text-2xl text-n-slate-12">
            {{ formatCurrency(spend.total_amount) }}
          </p>
          <p
            v-if="spend.total_amount === null"
            class="text-xs mt-1 text-n-amber-11"
          >
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_PENDING') }}
          </p>
          <p class="text-xs mt-1 text-n-slate-11">
            {{
              t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_COVERAGE', {
                captured: spend.coverage.ads_with_spend,
                total: spend.coverage.ads_with_leads,
              })
            }}
          </p>
        </div>
        <div class="min-w-[7rem]">
          <h4 class="m-0 text-sm font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_CREATED') }}
          </h4>
          <p class="mt-1 mb-0 text-2xl text-n-slate-12">
            {{ totals.lead_created }}
          </p>
          <p class="text-xs mt-1 text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.COST_PER_LEAD') }}:
            {{ formatCurrency(spend.costs.cost_per_lead) }}
          </p>
        </div>
        <div class="min-w-[7rem]">
          <h4 class="m-0 text-sm font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_CONTACTED') }}
          </h4>
          <p class="mt-1 mb-0 text-2xl text-n-slate-12">
            {{ totals.lead_contacted }}
          </p>
          <p
            class="text-xs mt-1"
            :class="statusClass(targetStatus(contactRate, { min: 0.5 }))"
          >
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.CONTACT_RATE') }}:
            {{ formatPercent(contactRate) }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.COST_PER_CONTACT') }}:
            {{ formatCurrency(spend.costs.cost_per_contact) }}
          </p>
        </div>
        <div class="min-w-[7rem]">
          <h4 class="m-0 text-sm font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_QUALIFIED') }}
          </h4>
          <p class="mt-1 mb-0 text-2xl text-n-slate-12">
            {{ totals.lead_qualified }}
          </p>
          <p
            class="text-xs mt-1"
            :class="
              statusClass(
                targetStatus(qualificationRateLeads, { min: 0.12, max: 0.15 })
              )
            "
          >
            {{ formatPercent(qualificationRateLeads) }}
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.OF_LEADS') }}
          </p>
          <p
            class="text-xs"
            :class="
              statusClass(
                targetStatus(qualificationRateContacted, {
                  min: 0.2,
                  max: 0.25,
                })
              )
            "
          >
            {{ formatPercent(qualificationRateContacted) }}
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.OF_CONTACTED') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{
              t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.COST_PER_QUALIFIED')
            }}: {{ formatCurrency(spend.costs.cost_per_qualified) }}
          </p>
        </div>
        <div class="min-w-[7rem]">
          <h4 class="m-0 text-sm font-medium text-n-slate-11">
            {{
              t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.APPOINTMENT_CREATED')
            }}
          </h4>
          <p class="mt-1 mb-0 text-2xl text-n-slate-12">
            {{ totals.appointment_created }}
          </p>
          <p
            class="text-xs mt-1"
            :class="
              statusClass(
                targetStatus(appointmentRateLeads, { min: 0.1, max: 0.15 })
              )
            "
          >
            {{ formatPercent(appointmentRateLeads) }}
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.OF_LEADS') }}
          </p>
          <p
            class="text-xs"
            :class="
              statusClass(
                targetStatus(appointmentRateQualified, { min: 0.7, max: 0.8 })
              )
            "
          >
            {{ formatPercent(appointmentRateQualified) }}
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.OF_QUALIFIED') }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{
              t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.COST_PER_APPOINTMENT')
            }}: {{ formatCurrency(spend.costs.cost_per_appointment) }}
          </p>
        </div>
        <div class="min-w-[7rem]">
          <h4 class="m-0 text-sm font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.VISIT_EFFECTIVE') }}
          </h4>
          <p class="mt-1 mb-0 text-2xl text-n-slate-12">
            {{ totals.visit_effective }}
          </p>
          <p
            class="text-xs mt-1"
            :class="statusClass(targetStatus(showRate, { min: 0.4, max: 0.5 }))"
          >
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SHOW_RATE') }}:
            {{ formatPercent(showRate) }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.NO_SHOW_RATE') }}:
            {{ formatPercent(noShowRate) }}
          </p>
          <p class="text-xs text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.COST_PER_VISIT') }}:
            {{ formatCurrency(spend.costs.cost_per_visit) }}
          </p>
        </div>
      </div>
    </div>

    <!-- Funnel -->
    <div
      class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
    >
      <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.FUNNEL_TITLE') }}
      </h3>
      <div class="flex flex-col gap-4">
        <FunnelStageMeter
          v-for="step in funnelMeterSteps"
          :key="step.stage"
          :icon="step.icon"
          :label="step.label"
          :count="step.count"
          :actual-percent="step.actualPercent"
          :taper-percent="step.taperPercent"
          :activity-count="step.seguimientoCount"
          :activity-tooltip="
            t('REVENUE_INTELLIGENCE_REPORTS.FUNNEL.SEGUIMIENTO_TOOLTIP')
          "
          :lost-count="step.lostCount"
          :lost-tooltip="t('REVENUE_INTELLIGENCE_REPORTS.FUNNEL.LOST_TOOLTIP')"
        />
      </div>
    </div>

    <!-- SLA del setter -->
    <div
      class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
    >
      <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_TITLE') }}
      </h3>
      <p class="text-xs text-n-slate-11 mb-4">
        {{
          t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_TARGET', { minutes: 5 })
        }}
      </p>
      <div v-if="sla && sla.responded_count > 0" class="flex flex-wrap gap-6">
        <div class="min-w-[6rem]">
          <h4 class="m-0 text-xs font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_MEDIAN') }}
          </h4>
          <p
            class="mt-1 mb-0 text-xl"
            :class="
              statusClass(
                targetStatus(sla.median_seconds, { max: sla.target_seconds })
              )
            "
          >
            {{ formatSeconds(sla.median_seconds) }}
          </p>
        </div>
        <div class="min-w-[6rem]">
          <h4 class="m-0 text-xs font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_AVG') }}
          </h4>
          <p class="mt-1 mb-0 text-xl text-n-slate-12">
            {{ formatSeconds(sla.avg_seconds) }}
          </p>
        </div>
        <div class="min-w-[6rem]">
          <h4 class="m-0 text-xs font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_P75') }}
          </h4>
          <p class="mt-1 mb-0 text-xl text-n-slate-12">
            {{ formatSeconds(sla.p75_seconds) }}
          </p>
        </div>
        <div
          v-for="bucketKey in [
            'under_5',
            'from_5_to_15',
            'from_15_to_30',
            'over_30',
          ]"
          :key="bucketKey"
          class="min-w-[6rem]"
        >
          <h4 class="m-0 text-xs font-medium text-n-slate-11">
            {{
              t(
                `REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_BUCKET_${bucketKey.toUpperCase()}`
              )
            }}
          </h4>
          <p class="mt-1 mb-0 text-xl text-n-slate-12">
            {{ sla.buckets[bucketKey].count }} ({{
              formatPercent(sla.buckets[bucketKey].rate)
            }})
          </p>
        </div>
        <div class="min-w-[6rem]">
          <h4 class="m-0 text-xs font-medium text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_PENDING') }}
          </h4>
          <p class="mt-1 mb-0 text-xl text-n-slate-12">
            {{ sla.pending_count }}
          </p>
        </div>
        <div v-if="sla.outliers_excluded_count > 0" class="min-w-[6rem]">
          <h4 class="m-0 text-xs font-medium text-n-slate-11">
            {{
              t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_OUTLIERS_EXCLUDED')
            }}
          </h4>
          <p
            class="mt-1 mb-0 text-xl text-n-slate-9"
            :title="
              t(
                'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_OUTLIERS_EXCLUDED_TOOLTIP'
              )
            "
          >
            {{ sla.outliers_excluded_count }}
          </p>
        </div>
      </div>
      <p v-else class="text-sm text-n-slate-11">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_NO_DATA') }}
      </p>
    </div>

    <!-- Por fuente (jerarquía existente) -->
    <div
      class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
    >
      <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.TITLE') }}
      </h3>
      <p class="text-sm text-n-slate-11 mb-4">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.DESCRIPTION') }}
      </p>
      <div
        v-if="!marketingRows.length"
        class="text-sm text-n-slate-11 py-4 text-center"
      >
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.EMPTY') }}
      </div>
      <table v-else class="woot-table w-full">
        <thead>
          <tr>
            <th>{{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SOURCE') }}</th>
            <th v-for="metric in MARKETING_METRIC_COLUMNS" :key="metric">
              {{ FUNNEL_LABELS[metric] || metric }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in marketingRows"
            :key="row.key"
            :class="row.level === 1 ? 'border-t-2 border-n-slate-6' : ''"
          >
            <td>
              <button
                v-if="row.expandable"
                type="button"
                class="inline-flex items-center gap-1 cursor-pointer bg-transparent border-0 p-0"
                :style="{ paddingLeft: `${row.level * 1.25}rem` }"
                :class="
                  row.level === 0
                    ? 'font-semibold text-n-slate-12'
                    : 'text-n-slate-11'
                "
                @click="toggleCampaign(row.key)"
              >
                <span class="text-xs w-3 inline-block">{{
                  row.expanded ? '▾' : '▸'
                }}</span>
                {{ row.label }}
              </button>
              <span
                v-else
                :style="{ paddingLeft: `${row.level * 1.25}rem` }"
                :class="
                  row.level === 0
                    ? 'font-semibold text-n-slate-12'
                    : 'text-n-slate-11'
                "
              >
                {{ row.label }}
              </span>
            </td>
            <td v-for="metric in MARKETING_METRIC_COLUMNS" :key="metric">
              {{ row.metrics[metric] || 0 }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Funnel y costo por anuncio -->
    <div
      class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
    >
      <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.AD_TABLE_TITLE') }}
      </h3>
      <div
        v-if="!adTable.length"
        class="text-sm text-n-slate-11 py-4 text-center"
      >
        {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.AD_TABLE_EMPTY') }}
      </div>
      <table v-else class="woot-table w-full">
        <thead>
          <tr>
            <th class="cursor-pointer" @click="setSort('ad')">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.AD_COLUMN') }}
            </th>
            <th class="cursor-pointer" @click="setSort('spend_amount')">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_COLUMN') }}
            </th>
            <th
              v-for="metric in AD_TABLE_METRICS"
              :key="metric"
              class="cursor-pointer"
              @click="setSort(metric)"
            >
              {{ FUNNEL_LABELS[metric] || metric }}
            </th>
            <th class="cursor-pointer" @click="setSort('cost_per_visit')">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.COST_PER_VISIT') }}
            </th>
            <th class="cursor-pointer" @click="setSort('show_rate')">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SHOW_RATE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in adTable"
            :key="`${row.campaign_name}::${row.adset_name}::${row.advert_name}`"
          >
            <td>
              <div class="font-medium text-n-slate-12">
                {{ row.advert_name }}
              </div>
              <div class="text-xs text-n-slate-11">
                {{ row.campaign_name }} · {{ row.adset_name }}
              </div>
            </td>
            <td>
              <button
                v-if="row.spend_source !== 'meta_api'"
                type="button"
                class="cursor-pointer bg-transparent border-0 p-0 underline"
                @click="openNewSpend"
              >
                {{ formatCurrency(row.spend_amount) }}
              </button>
              <span v-else class="inline-flex items-center gap-1">
                {{ formatCurrency(row.spend_amount) }}
                <span
                  class="text-xxs px-1 rounded bg-n-teal-3 text-n-teal-11"
                  :title="
                    t(
                      'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_SOURCE_META_API_TOOLTIP'
                    )
                  "
                >
                  {{
                    t(
                      'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_SOURCE_META_API'
                    )
                  }}
                </span>
              </span>
            </td>
            <td v-for="metric in AD_TABLE_METRICS" :key="metric">
              {{ row.metrics[metric] || 0 }}
            </td>
            <td>{{ formatCurrency(row.costs.cost_per_visit) }}</td>
            <td>{{ formatPercent(row.rates.show_rate) }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Inversión capturada -->
    <div
      class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
    >
      <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
        {{
          t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.MANAGE_TITLE')
        }}
      </h3>
      <div
        v-if="!adSpends.length"
        class="text-sm text-n-slate-11 py-4 text-center"
      >
        {{
          t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.MANAGE_EMPTY')
        }}
      </div>
      <table v-else class="woot-table w-full">
        <thead>
          <tr>
            <th>{{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.AD_COLUMN') }}</th>
            <th>
              {{
                t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.PERIOD')
              }}
            </th>
            <th>
              {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_COLUMN') }}
            </th>
            <th>
              {{
                t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.ACTIONS')
              }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="adSpend in adSpends" :key="adSpend.id">
            <td>
              <div class="text-n-slate-12">
                {{
                  adSpend.advert_name ||
                  adSpend.adset_name ||
                  adSpend.campaign_name
                }}
              </div>
              <div class="text-xs text-n-slate-11">
                {{ adSpend.campaign_name }}
              </div>
            </td>
            <td>{{ adSpend.period_start }} — {{ adSpend.period_end }}</td>
            <td>{{ formatCurrency(adSpend.amount) }}</td>
            <td class="flex gap-2">
              <button
                type="button"
                class="cursor-pointer bg-transparent border-0 p-0 underline text-xs"
                @click="openEditSpend(adSpend)"
              >
                {{
                  t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.TITLE')
                }}
              </button>
              <button
                type="button"
                class="cursor-pointer bg-transparent border-0 p-0 underline text-xs text-n-ruby-11"
                @click="deleteSpend(adSpend)"
              >
                {{
                  t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.DELETE')
                }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <MarketingSpendModal
      ref="spendModalRef"
      :filter-options="filterOptions"
      @saved="onSpendSaved"
    />
  </div>
</template>
