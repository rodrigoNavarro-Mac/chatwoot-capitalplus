<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ReportsAPI from 'dashboard/api/reports';
import Spinner from 'shared/components/Spinner.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  // { from, to, desarrollo, campaignId, adsetId, advertId } -- from/to ya en segundos unix (mismo
  // formato que RevenueIntelligenceReport.vue#fetchReport le manda al reporte principal), el resto
  // sin envolver (undefined si no hay filtro activo).
  filters: { type: Object, required: true },
  // Qué métrica preseleccionar al entrar a la pestaña -- normalmente 'setter' salvo que el usuario
  // haya llegado aquí desde el botón "Ver detalle" de una tarjeta SLA específica (ver
  // SlaSummaryCard.vue / MarketingTab.vue @view-sla-detail).
  initialMetric: { type: String, default: 'setter' },
});

const { t } = useI18n();

// Diseñado como lista para poder agregar más auditorías después (ej. tiempo a calificación, a
// cita) sin tocar la estructura del componente -- ver plan de Auditoría.
const AUDIT_METRICS = [
  {
    value: 'setter',
    labelKey: 'REVENUE_INTELLIGENCE_REPORTS.AUDIT.METRIC_OPTIONS.SETTER',
  },
  {
    value: 'call_attempt',
    labelKey: 'REVENUE_INTELLIGENCE_REPORTS.AUDIT.METRIC_OPTIONS.CALL_ATTEMPT',
  },
];
const metricOptions = computed(() =>
  AUDIT_METRICS.map(metric => ({
    value: metric.value,
    label: t(metric.labelKey),
  }))
);

const selectedMetric = ref(props.initialMetric);

const isLoading = ref(false);
const auditData = ref(null); // { total_matching_count, rows }

const hasValidRange = computed(
  () => !!(props.filters.from && props.filters.to)
);

const fetchAudit = async () => {
  if (!hasValidRange.value) return;

  isLoading.value = true;
  try {
    const response = await ReportsAPI.getRevenueIntelligenceSlaAudit({
      from: props.filters.from,
      to: props.filters.to,
      desarrollo: props.filters.desarrollo,
      campaign_id: props.filters.campaignId,
      adset_id: props.filters.adsetId,
      advert_id: props.filters.advertId,
      metric: selectedMetric.value,
    });
    auditData.value = response.data;
  } catch (error) {
    useAlert(t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchAudit);
watch([() => props.filters, selectedMetric], fetchAudit, { deep: true });

const rows = computed(() => auditData.value?.rows ?? []);
const totalMatchingCount = computed(
  () => auditData.value?.total_matching_count ?? 0
);
const excludedCount = computed(
  () => rows.value.filter(row => row.excluded).length
);
const isTruncated = computed(
  () => totalMatchingCount.value > rows.value.length
);

const formatMinutes = seconds =>
  seconds == null ? '—' : (seconds / 60).toFixed(1);
const formatDateTime = value =>
  value ? new Date(value).toLocaleString('es-MX') : '—';

const campaignLabel = row =>
  [row.campaign_name, row.adset_name, row.advert_name]
    .filter(Boolean)
    .join(' / ') || '—';
</script>

<template>
  <div
    class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
  >
    <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
      {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TITLE') }}
    </h3>
    <p class="text-sm text-n-slate-11 mb-4">
      {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.DESCRIPTION') }}
    </p>

    <div class="mb-4">
      <label class="text-xs text-n-slate-11 mb-1 block">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.METRIC_LABEL') }}
      </label>
      <Select v-model="selectedMetric" :options="metricOptions" />
    </div>

    <div v-if="isLoading" class="flex justify-center py-8">
      <Spinner />
    </div>
    <template v-else>
      <p v-if="rows.length" class="text-xs text-n-slate-10 mb-3">
        {{
          t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.SUMMARY', {
            shown: rows.length,
            total: totalMatchingCount,
            excluded: excludedCount,
          })
        }}
      </p>
      <div v-if="!rows.length" class="text-sm text-n-slate-11 py-4 text-center">
        {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.EMPTY') }}
      </div>
      <div v-else class="overflow-x-auto">
        <table class="woot-table w-full">
          <thead>
            <tr>
              <th>{{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.LEAD') }}</th>
              <th>
                {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.PHONE') }}
              </th>
              <th>
                {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.CAMPAIGN') }}
              </th>
              <th>
                {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.DEVELOPMENT') }}
              </th>
              <th>
                {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.CREATED_AT') }}
              </th>
              <th>
                {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.EVENT_AT') }}
              </th>
              <th>
                {{
                  t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.CLOCK_MINUTES')
                }}
              </th>
              <th>
                {{
                  t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.BUSINESS_MINUTES')
                }}
              </th>
              <th>
                {{ t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TABLE.EXCLUDED') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in rows" :key="row.id">
              <td>{{ row.name || row.zoho_lead_id }}</td>
              <td>{{ row.phone || '—' }}</td>
              <td>{{ campaignLabel(row) }}</td>
              <td>{{ row.desarrollo || '—' }}</td>
              <td>{{ formatDateTime(row.created_at_source) }}</td>
              <td>{{ formatDateTime(row.event_at) }}</td>
              <td class="tabular-nums">
                {{ formatMinutes(row.clock_seconds) }}
              </td>
              <td class="tabular-nums">
                {{ formatMinutes(row.business_seconds) }}
              </td>
              <td>
                <span
                  v-if="row.excluded"
                  class="px-2 py-0.5 rounded text-xs bg-n-amber-3 text-n-amber-11"
                  :title="
                    t(
                      'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_OUTLIERS_EXCLUDED_TOOLTIP'
                    )
                  "
                >
                  {{
                    t(
                      'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_OUTLIERS_EXCLUDED'
                    )
                  }}
                </span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-if="isTruncated" class="text-xs text-n-slate-10 mt-2">
        {{
          t('REVENUE_INTELLIGENCE_REPORTS.AUDIT.TRUNCATED', {
            shown: rows.length,
            total: totalMatchingCount,
          })
        }}
      </p>
    </template>
  </div>
</template>
