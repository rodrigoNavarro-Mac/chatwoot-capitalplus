<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import TemplatesReportTable from './components/TemplatesReportTable.vue';
import TemplatesReportTimeseriesTable from './components/TemplatesReportTimeseriesTable.vue';
import Spinner from 'shared/components/Spinner.vue';

const { t } = useI18n();

const toDateInputValue = date => date.toISOString().slice(0, 10);

const filters = ref({
  since: toDateInputValue(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)),
  until: toDateInputValue(new Date()),
  groupBy: 'day',
});

const isLoading = ref(false);
const totals = ref([]);
const series = ref([]);

const toUnixSeconds = (dateValue, endOfDay = false) => {
  const date = new Date(`${dateValue}T${endOfDay ? '23:59:59' : '00:00:00'}`);
  return Math.floor(date.getTime() / 1000).toString();
};

const requestPayload = computed(() => ({
  from: toUnixSeconds(filters.value.since),
  to: toUnixSeconds(filters.value.until, true),
  groupBy: filters.value.groupBy,
}));

const kpiCards = computed(() => {
  if (!totals.value.length) return [];
  const totalSent = totals.value.reduce((sum, row) => sum + row.sent, 0);
  const totalResponded = totals.value.reduce(
    (sum, row) => sum + row.responded,
    0
  );
  const overallResponseRate = totalSent
    ? Math.round((totalResponded / totalSent) * 10000) / 100
    : 0;
  const bestTemplate = [...totals.value]
    .filter(row => row.sent >= 5)
    .sort((a, b) => b.response_rate - a.response_rate)[0];

  return [
    {
      key: 'total_sent',
      label: t('TEMPLATES_REPORTS.KPI.TOTAL_SENT'),
      value: String(totalSent),
    },
    {
      key: 'overall_response_rate',
      label: t('TEMPLATES_REPORTS.KPI.OVERALL_RESPONSE_RATE'),
      value: `${overallResponseRate}%`,
    },
    {
      key: 'best_template',
      label: t('TEMPLATES_REPORTS.KPI.BEST_TEMPLATE'),
      value: bestTemplate
        ? `${bestTemplate.template_name} (${bestTemplate.response_rate}%)`
        : '—',
    },
  ];
});

const fetchReport = async () => {
  isLoading.value = true;
  try {
    const [totalsRes, seriesRes] = await Promise.all([
      ReportsAPI.getTemplatesReport(requestPayload.value),
      ReportsAPI.getTemplatesTimeseries(requestPayload.value),
    ]);
    totals.value = totalsRes.data;
    series.value = seriesRes.data;
  } catch (error) {
    useAlert(t('TEMPLATES_REPORTS.ERRORS.FETCH'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchReport);
watch(filters, fetchReport, { deep: true });
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <ReportHeader
        :header-title="t('TEMPLATES_REPORTS.HEADER')"
        :header-description="t('TEMPLATES_REPORTS.DESCRIPTION')"
      />

      <div class="flex flex-wrap items-end gap-3 mb-6">
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('TEMPLATES_REPORTS.FILTERS.SINCE') }}
          </label>
          <input
            v-model="filters.since"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('TEMPLATES_REPORTS.FILTERS.UNTIL') }}
          </label>
          <input
            v-model="filters.until"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('TEMPLATES_REPORTS.FILTERS.GROUP_BY') }}
          </label>
          <select v-model="filters.groupBy" class="!mb-0 !h-8 text-sm">
            <option value="day">
              {{ t('TEMPLATES_REPORTS.FILTERS.GROUP_BY_OPTIONS.day') }}
            </option>
            <option value="week">
              {{ t('TEMPLATES_REPORTS.FILTERS.GROUP_BY_OPTIONS.week') }}
            </option>
            <option value="month">
              {{ t('TEMPLATES_REPORTS.FILTERS.GROUP_BY_OPTIONS.month') }}
            </option>
          </select>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner />
      </div>

      <template v-else>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <ReportMetricCard
            v-for="card in kpiCards"
            :key="card.key"
            :label="card.label"
            :value="card.value"
            :info-text="card.label"
          />
        </div>

        <TemplatesReportTable :rows="totals" />
        <TemplatesReportTimeseriesTable :rows="series" />
      </template>
    </div>
  </div>
</template>
