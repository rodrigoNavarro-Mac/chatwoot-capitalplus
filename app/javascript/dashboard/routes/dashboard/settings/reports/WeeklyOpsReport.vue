<script setup>
import { ref, computed, nextTick, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import WeeklyOpsReportsAPI from 'dashboard/api/weeklyOpsReports';
import { downloadBlobFile } from 'dashboard/helper/downloadHelper';
import ReportHeader from './components/ReportHeader.vue';
import FunnelStageMeter from './components/FunnelStageMeter.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import ReportBrandingPanel from './components/ReportBrandingPanel.vue';
import CardAnalysisNote from './components/CardAnalysisNote.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import LineChart from 'shared/components/charts/LineChart.vue';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

const STAGE_ICONS = {
  leads: 'i-lucide-users',
  customer_replied: 'i-lucide-message-circle',
  has_deal: 'i-lucide-handshake',
  visita_efectiva: 'i-lucide-map-pin',
  closed_won: 'i-lucide-trophy',
};
const STAGE_TAPER = {
  leads: 100,
  customer_replied: 92,
  has_deal: 84,
  visita_efectiva: 80,
  closed_won: 76,
};

const toDateInputValue = date => date.toISOString().slice(0, 10);

// Por defecto, la última semana lunes-domingo ya cerrada.
const defaultRange = () => {
  const now = new Date();
  const day = now.getDay();
  const diffToLastMonday = day === 0 ? 13 : day + 6;
  const since = new Date(now);
  since.setDate(now.getDate() - diffToLastMonday);
  const until = new Date(since);
  until.setDate(since.getDate() + 6);
  return { since: toDateInputValue(since), until: toDateInputValue(until) };
};

const filters = ref({ inboxId: '', periodType: 'week', ...defaultRange() });

// Valores solo para los pickers de mes/trimestre — filters.since/until siguen siendo la fuente de
// verdad que consume canGenerate/fetchOrGenerate/loadExistingReport sin cambios.
const pad2 = value => String(value).padStart(2, '0');

const defaultMonthValue = () => {
  const now = new Date();
  const lastClosedMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  return `${lastClosedMonth.getFullYear()}-${pad2(lastClosedMonth.getMonth() + 1)}`;
};

const defaultQuarter = () => {
  const now = new Date();
  const currentQuarter = Math.floor(now.getMonth() / 3) + 1;
  return currentQuarter === 1
    ? { year: now.getFullYear() - 1, quarter: 4 }
    : { year: now.getFullYear(), quarter: currentQuarter - 1 };
};

const monthValue = ref(defaultMonthValue());
const quarterDefaults = defaultQuarter();
const quarterYear = ref(quarterDefaults.year);
const quarterNumber = ref(quarterDefaults.quarter);

const applyMonthRange = () => {
  const [year, month] = monthValue.value.split('-').map(Number);
  filters.value.since = toDateInputValue(new Date(year, month - 1, 1));
  filters.value.until = toDateInputValue(new Date(year, month, 0));
};

const applyQuarterRange = () => {
  const startMonth = (quarterNumber.value - 1) * 3;
  filters.value.since = toDateInputValue(
    new Date(quarterYear.value, startMonth, 1)
  );
  filters.value.until = toDateInputValue(
    new Date(quarterYear.value, startMonth + 3, 0)
  );
};

watch(
  () => filters.value.periodType,
  periodType => {
    if (periodType === 'month') applyMonthRange();
    else if (periodType === 'quarter') applyQuarterRange();
    else Object.assign(filters.value, defaultRange());
  }
);
watch(monthValue, () => {
  if (filters.value.periodType === 'month') applyMonthRange();
});
watch([quarterYear, quarterNumber], () => {
  if (filters.value.periodType === 'quarter') applyQuarterRange();
});

const isLoading = ref(false);
const report = ref(null);
const isDownloading = ref(false);

const contactTimeChartRef = ref(null);
const cadenceChartRef = ref(null);
const leadsTimelineChartRef = ref(null);
const channelComparisonChartRef = ref(null);
const qualityBySourceChartRef = ref(null);
const conversionTotalsChartRef = ref(null);

const isCompleteDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value);
const canGenerate = computed(
  () =>
    !!filters.value.inboxId &&
    isCompleteDate(filters.value.since) &&
    isCompleteDate(filters.value.until)
);

// UTC explícito (sufijo Z): el backend interpreta since/until como epoch en UTC
// (DateRangeHelper#parse_date_time). Sin el "Z", el navegador arma la fecha en su zona horaria
// local, así que en cualquier huso detrás de UTC (ej. México, UTC-6) "9 de agosto 23:59:59 local"
// cae en "10 de agosto" al convertir a UTC, corriendo el reporte un día.
const toUnixSeconds = (dateValue, endOfDay = false) => {
  const date = new Date(`${dateValue}T${endOfDay ? '23:59:59' : '00:00:00'}Z`);
  return Math.floor(date.getTime() / 1000).toString();
};

const kpis = computed(() => report.value?.kpis || null);

const contactTimeChartData = computed(() => {
  const current = kpis.value?.contact_time || {};
  const previous = kpis.value?.comparison?.contact_time || {};
  return {
    labels: [
      t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE'),
      t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME'),
    ],
    datasets: [
      {
        label: t('WEEKLY_OPS_REPORTS.CHART.CURRENT_PERIOD'),
        backgroundColor: '#1f77b4',
        data: [current.first_response || 0, current.reply_time || 0],
      },
      {
        label: t('WEEKLY_OPS_REPORTS.CHART.PREVIOUS_PERIOD'),
        backgroundColor: '#c7c7c7',
        data: [previous.first_response || 0, previous.reply_time || 0],
      },
    ],
  };
});

const discardReasonsTotal = computed(() => {
  const reasons = kpis.value?.zoho_leads?.discard_reasons || {};
  return Object.values(reasons).reduce((sum, count) => sum + count, 0);
});

const percentOf = (count, total) =>
  total > 0 ? `${((count / total) * 100).toFixed(1)}%` : '0%';

const formatDuration = seconds => {
  if (seconds === null || seconds === undefined) return '—';
  return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
};

const cadenceChartData = computed(() => {
  const byStatus = kpis.value?.cadences?.by_status || {};
  const labels = Object.keys(byStatus);
  return {
    labels,
    datasets: [
      {
        label: t('WEEKLY_OPS_REPORTS.CADENCES.BY_STATUS'),
        backgroundColor: '#ff7f0e',
        data: labels.map(label => byStatus[label]),
      },
    ],
  };
});

const TIMELINE_TITLE_KEYS = {
  day: 'WEEKLY_OPS_REPORTS.LEADS_TIMELINE.TITLE_DAY',
  week: 'WEEKLY_OPS_REPORTS.LEADS_TIMELINE.TITLE_WEEK',
  month: 'WEEKLY_OPS_REPORTS.LEADS_TIMELINE.TITLE_MONTH',
};

const leadsTimelineTitle = computed(() => {
  const granularity = kpis.value?.zoho_leads_timeline?.granularity || 'day';
  return t(TIMELINE_TITLE_KEYS[granularity] || TIMELINE_TITLE_KEYS.day);
});

// Los labels del timeline ya vienen formateados para mostrar ("03/08"), así que el día de la
// semana real se resuelve aparte a partir de `dates` (ISO) para pintar sábado/domingo distinto —
// mismo objetivo visual que las líneas verticales punteadas del reporte viejo, sin depender de
// chartjs-plugin-annotation (no está instalado en este proyecto).
const isWeekendDate = dateValue => {
  if (!dateValue) return false;
  const day = new Date(`${dateValue}T00:00:00Z`).getUTCDay();
  return day === 0 || day === 6;
};

const leadsTimelineChartData = computed(() => {
  const timeline = kpis.value?.zoho_leads_timeline || {
    labels: [],
    counts: [],
    dates: [],
  };
  const isDayGranularity =
    (kpis.value?.zoho_leads_timeline?.granularity || 'day') === 'day';
  const pointBackgroundColor = isDayGranularity
    ? timeline.labels.map((_, index) =>
        isWeekendDate(timeline.dates?.[index]) ? '#d62728' : '#2ca02c'
      )
    : '#2ca02c';
  return {
    labels: timeline.labels,
    datasets: [
      {
        label: leadsTimelineTitle.value,
        borderColor: '#2ca02c',
        backgroundColor: '#2ca02c',
        pointBackgroundColor,
        fill: false,
        data: timeline.counts,
      },
    ],
  };
});

const channelComparisonChartData = computed(() => {
  const current = kpis.value?.zoho_leads?.by_source || {};
  const previous = kpis.value?.comparison?.zoho_leads?.by_source || {};
  const labels = [
    ...new Set([...Object.keys(current), ...Object.keys(previous)]),
  ];
  return {
    labels,
    datasets: [
      {
        label: t('WEEKLY_OPS_REPORTS.CHART.CURRENT_PERIOD'),
        backgroundColor: '#1f77b4',
        data: labels.map(label => current[label] || 0),
      },
      {
        label: t('WEEKLY_OPS_REPORTS.CHART.PREVIOUS_PERIOD'),
        backgroundColor: '#c7c7c7',
        data: labels.map(label => previous[label] || 0),
      },
    ],
  };
});

const qualityBySourceChartData = computed(() => {
  const bySource = kpis.value?.zoho_leads?.quality_by_source || {};
  const labels = Object.keys(bySource);
  return {
    labels,
    datasets: [
      {
        label: t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS'),
        backgroundColor: '#c7c7c7',
        data: labels.map(label => bySource[label]?.total || 0),
      },
      {
        label: t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.CONTACTED'),
        backgroundColor: '#2ca02c',
        data: labels.map(label => bySource[label]?.quality || 0),
      },
    ],
  };
});

// Total del desarrollo, no por asesor — el "Owner" en Zoho no necesariamente refleja qué asesor
// de Chatwoot atendió al cliente, así que desglosar por dueño daba una lectura equivocada de quién
// "convierte más" (ver V2::Reports::ZohoLeadsMetrics#conversion_totals).
const conversionTotalsChartData = computed(() => {
  const totals = kpis.value?.conversion_totals;
  if (!totals) return { labels: [], datasets: [] };

  return {
    labels: [
      t('WEEKLY_OPS_REPORTS.CONVERSION_BY_OWNER.CONVERTED'),
      t('WEEKLY_OPS_REPORTS.CONVERSION_BY_OWNER.LOST'),
    ],
    datasets: [
      {
        backgroundColor: ['#2ca02c', '#d62728'],
        data: [totals.converted, totals.lost],
      },
    ],
  };
});

// El backend deja el reporte en "pending" y arma los KPIs + análisis de IA en segundo plano (ver
// Reports::GenerateOnDemandWeeklyOpsReportJob) porque esa llamada al LLM ya no cabe de forma
// confiable en los 15s del timeout de un request HTTP normal. Mientras esté "pending" se hace
// polling a GET .../weekly_ops_reports/:id hasta que quede "completed" o "failed".
const POLL_INTERVAL_MS = 3000;
let pollTimeoutId = null;

const stopPolling = () => {
  if (pollTimeoutId) {
    clearTimeout(pollTimeoutId);
    pollTimeoutId = null;
  }
};

const pollReport = async () => {
  if (!report.value || report.value.status !== 'pending') return;

  try {
    const response = await WeeklyOpsReportsAPI.getReport(
      filters.value.inboxId,
      report.value.id
    );
    report.value = response.data;
  } catch (error) {
    // Silencioso: reintenta en el siguiente tick en vez de tumbar el polling por un fallo puntual.
  }

  if (report.value?.status === 'pending') {
    pollTimeoutId = setTimeout(pollReport, POLL_INTERVAL_MS);
    return;
  }

  isLoading.value = false;
  if (report.value?.status === 'failed') {
    useAlert(t('WEEKLY_OPS_REPORTS.ERRORS.GENERATE'));
  }
};

onBeforeUnmount(stopPolling);

// Si ya existe un reporte generado para el inbox, el rango de fechas y el tipo de periodo
// seleccionados, lo precarga en vez de dejar la pantalla vacía esperando a que el usuario le dé
// "Generar reporte" de nuevo.
const loadExistingReport = async () => {
  stopPolling();
  report.value = null;
  if (!canGenerate.value) return;

  isLoading.value = true;
  try {
    const { data } = await WeeklyOpsReportsAPI.getReports(
      filters.value.inboxId
    );
    const match = data.find(
      existing =>
        existing.period_start === filters.value.since &&
        existing.period_end === filters.value.until &&
        existing.period_type === filters.value.periodType &&
        existing.status === 'completed'
    );
    if (match) {
      const response = await WeeklyOpsReportsAPI.getReport(
        filters.value.inboxId,
        match.id
      );
      report.value = response.data;
    }
  } catch (error) {
    // Silencioso: si falla la precarga, el usuario igual puede generar manualmente.
  } finally {
    isLoading.value = false;
  }
};

watch(
  () => [
    filters.value.inboxId,
    filters.value.since,
    filters.value.until,
    filters.value.periodType,
  ],
  loadExistingReport
);

const fetchOrGenerate = async () => {
  if (!canGenerate.value) return;

  stopPolling();
  isLoading.value = true;
  try {
    const response = await WeeklyOpsReportsAPI.generateReport(
      filters.value.inboxId,
      {
        since: toUnixSeconds(filters.value.since),
        until: toUnixSeconds(filters.value.until, true),
        periodType: filters.value.periodType,
      }
    );
    report.value = response.data;
    if (report.value.status === 'pending') {
      pollTimeoutId = setTimeout(pollReport, POLL_INTERVAL_MS);
    } else {
      isLoading.value = false;
    }
  } catch (error) {
    useAlert(t('WEEKLY_OPS_REPORTS.ERRORS.GENERATE'));
    isLoading.value = false;
  }
};

const downloadPdf = async () => {
  if (!report.value) return;

  isDownloading.value = true;
  try {
    await nextTick();
    // Mismo orden que las cards en pantalla — PDF/DOCX insertan cada gráfica en el orden que
    // llega este array, y usan `key` (no el título, que está traducido) para encontrar el
    // mini-análisis de IA correspondiente en report.card_analyses.
    const chartImages = [
      leadsTimelineChartRef.value?.chart && {
        key: 'leads_timeline',
        title: leadsTimelineTitle.value,
        data_url: leadsTimelineChartRef.value.chart.toBase64Image(),
      },
      contactTimeChartRef.value?.chart && {
        key: 'contact_time',
        title: t('WEEKLY_OPS_REPORTS.CONTACT_TIME.TITLE'),
        data_url: contactTimeChartRef.value.chart.toBase64Image(),
      },
      conversionTotalsChartRef.value?.chart && {
        key: 'conversion_totals',
        title: t('WEEKLY_OPS_REPORTS.CONVERSION_BY_OWNER.TITLE'),
        data_url: conversionTotalsChartRef.value.chart.toBase64Image(),
      },
      qualityBySourceChartRef.value?.chart && {
        key: 'quality_by_source',
        title: t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.QUALITY_BY_SOURCE_TITLE'),
        data_url: qualityBySourceChartRef.value.chart.toBase64Image(),
      },
      channelComparisonChartRef.value?.chart && {
        key: 'channel_comparison',
        title: t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.CHANNEL_COMPARISON_TITLE'),
        data_url: channelComparisonChartRef.value.chart.toBase64Image(),
      },
      cadenceChartRef.value?.chart && {
        key: 'cadences',
        title: t('WEEKLY_OPS_REPORTS.CADENCES.BY_STATUS'),
        data_url: cadenceChartRef.value.chart.toBase64Image(),
      },
    ].filter(Boolean);

    const response = await WeeklyOpsReportsAPI.downloadPdf(
      filters.value.inboxId,
      report.value.id,
      chartImages
    );
    downloadBlobFile(
      `reporte-semanal-${report.value.inbox_id}-${report.value.period_start}.pdf`,
      response.data
    );
  } catch (error) {
    useAlert(t('WEEKLY_OPS_REPORTS.ERRORS.DOWNLOAD'));
  } finally {
    isDownloading.value = false;
  }
};
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <ReportHeader
        :header-title="t('WEEKLY_OPS_REPORTS.HEADER')"
        :header-description="t('WEEKLY_OPS_REPORTS.DESCRIPTION')"
      >
        <Button
          size="sm"
          variant="outline"
          icon="i-lucide-download"
          :is-loading="isDownloading"
          :disabled="!report || report.status !== 'completed'"
          :label="t('WEEKLY_OPS_REPORTS.DOWNLOAD_PDF')"
          @click="downloadPdf"
        />
      </ReportHeader>

      <div class="flex flex-wrap items-end gap-3 mb-6">
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('WEEKLY_OPS_REPORTS.FILTERS.INBOX') }}
          </label>
          <select v-model="filters.inboxId" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{ t('WEEKLY_OPS_REPORTS.FILTERS.SELECT_INBOX') }}
            </option>
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('WEEKLY_OPS_REPORTS.FILTERS.PERIOD_TYPE') }}
          </label>
          <select v-model="filters.periodType" class="!mb-0 !h-8 text-sm">
            <option value="week">
              {{ t('WEEKLY_OPS_REPORTS.FILTERS.WEEK') }}
            </option>
            <option value="month">
              {{ t('WEEKLY_OPS_REPORTS.FILTERS.MONTH') }}
            </option>
            <option value="quarter">
              {{ t('WEEKLY_OPS_REPORTS.FILTERS.QUARTER') }}
            </option>
          </select>
        </div>

        <template v-if="filters.periodType === 'week'">
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">
              {{ t('WEEKLY_OPS_REPORTS.FILTERS.SINCE') }}
            </label>
            <input
              v-model="filters.since"
              type="date"
              class="!mb-0 !h-8 text-sm"
            />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">
              {{ t('WEEKLY_OPS_REPORTS.FILTERS.UNTIL') }}
            </label>
            <input
              v-model="filters.until"
              type="date"
              class="!mb-0 !h-8 text-sm"
            />
          </div>
        </template>

        <div
          v-else-if="filters.periodType === 'month'"
          class="flex flex-col gap-1"
        >
          <label class="text-xs text-n-slate-11">
            {{ t('WEEKLY_OPS_REPORTS.FILTERS.MONTH') }}
          </label>
          <input v-model="monthValue" type="month" class="!mb-0 !h-8 text-sm" />
        </div>

        <template v-else>
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">
              {{ t('WEEKLY_OPS_REPORTS.FILTERS.QUARTER') }}
            </label>
            <select v-model.number="quarterNumber" class="!mb-0 !h-8 text-sm">
              <option :value="1">
                {{ t('WEEKLY_OPS_REPORTS.FILTERS.Q1') }}
              </option>
              <option :value="2">
                {{ t('WEEKLY_OPS_REPORTS.FILTERS.Q2') }}
              </option>
              <option :value="3">
                {{ t('WEEKLY_OPS_REPORTS.FILTERS.Q3') }}
              </option>
              <option :value="4">
                {{ t('WEEKLY_OPS_REPORTS.FILTERS.Q4') }}
              </option>
            </select>
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-xs text-n-slate-11">&nbsp;</label>
            <input
              v-model.number="quarterYear"
              type="number"
              class="!mb-0 !h-8 text-sm w-24"
            />
          </div>
        </template>

        <Button
          size="sm"
          icon="i-lucide-sparkles"
          :is-loading="isLoading"
          :disabled="!canGenerate"
          :label="t('WEEKLY_OPS_REPORTS.GENERATE')"
          @click="fetchOrGenerate"
        />
      </div>

      <ReportBrandingPanel v-if="filters.inboxId" :inbox-id="filters.inboxId" />

      <div v-if="isLoading" class="flex flex-col items-center gap-3 py-8">
        <Spinner />
        <p
          v-if="report?.status === 'pending'"
          class="text-sm text-n-slate-11 m-0"
        >
          {{ t('WEEKLY_OPS_REPORTS.GENERATING') }}
        </p>
      </div>

      <div
        v-else-if="!report || report.status !== 'completed'"
        class="text-sm text-n-slate-11 py-8 text-center rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
      >
        {{
          report?.status === 'failed'
            ? t('WEEKLY_OPS_REPORTS.ERRORS.FAILED')
            : t('WEEKLY_OPS_REPORTS.EMPTY')
        }}
      </div>

      <template v-else>
        <div
          class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <ReportMetricCard
            :label="t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE')"
            :value="`${kpis.contact_time.first_response ?? '—'} min`"
            :info-text="
              t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE_INFO')
            "
          />
          <ReportMetricCard
            :label="t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME')"
            :value="`${kpis.contact_time.reply_time ?? '—'} min`"
            :info-text="t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME_INFO')"
          />
          <ReportMetricCard
            :label="t('WEEKLY_OPS_REPORTS.VOLUME.NEW_CONVERSATIONS')"
            :value="String(kpis.volume.new_conversations)"
            :info-text="t('WEEKLY_OPS_REPORTS.VOLUME.NEW_CONVERSATIONS_INFO')"
          />
          <ReportMetricCard
            :label="t('WEEKLY_OPS_REPORTS.CADENCES.RESPONSE_RATE')"
            :value="`${kpis.cadences.response_rate ?? 0}%`"
            :info-text="t('WEEKLY_OPS_REPORTS.CADENCES.RESPONSE_RATE_INFO')"
          />
          <template v-if="kpis.deals_created">
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.DEALS.TOTAL')"
              :value="String(kpis.deals_created.total)"
              :info-text="t('WEEKLY_OPS_REPORTS.DEALS.TOTAL_INFO')"
            />
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.DEALS.CONVERSION_RATE')"
              :value="`${kpis.deals_created.conversion_rate}%`"
              :info-text="t('WEEKLY_OPS_REPORTS.DEALS.CONVERSION_RATE_INFO')"
            />
          </template>
        </div>

        <div
          v-if="kpis.deals_activity"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.DEALS_ACTIVITY.TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.deals_activity" />
          <div class="grid grid-cols-3 gap-4">
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.DEALS_ACTIVITY.TOTAL')"
              :value="String(kpis.deals_activity.total)"
              :info-text="t('WEEKLY_OPS_REPORTS.DEALS_ACTIVITY.TOTAL_INFO')"
            />
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.DEALS_ACTIVITY.VISITA_EFECTIVA')"
              :value="String(kpis.deals_activity.visita_efectiva)"
              :info-text="
                t('WEEKLY_OPS_REPORTS.DEALS_ACTIVITY.VISITA_EFECTIVA_INFO')
              "
            />
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.DEALS_ACTIVITY.CLOSED_WON')"
              :value="String(kpis.deals_activity.closed_won)"
              :info-text="
                t('WEEKLY_OPS_REPORTS.DEALS_ACTIVITY.CLOSED_WON_INFO')
              "
            />
          </div>
        </div>

        <div
          v-if="report.llm_analysis"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ANALYSIS.TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 whitespace-pre-line m-0">
            {{ report.llm_analysis }}
          </p>
        </div>

        <div
          v-if="
            kpis.zoho_leads_timeline && kpis.zoho_leads_timeline.labels.length
          "
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ leadsTimelineTitle }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.leads_timeline" />
          <div class="h-64">
            <LineChart
              ref="leadsTimelineChartRef"
              :collection="leadsTimelineChartData"
            />
          </div>
        </div>

        <div
          v-if="kpis.pipeline"
          class="flex flex-col gap-5 mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 m-0">
            {{ t('WEEKLY_OPS_REPORTS.PIPELINE.TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.pipeline" />
          <FunnelStageMeter
            v-for="stage in kpis.pipeline.stages"
            :key="stage.stage"
            :icon="STAGE_ICONS[stage.stage]"
            :label="t(`SALES_FUNNEL_REPORTS.STAGES.${stage.stage}`)"
            :count="stage.count"
            :actual-percent="stage.actual_percent"
            :target-percent="stage.target_percent"
            :delta="stage.delta"
            :taper-percent="STAGE_TAPER[stage.stage]"
          />
        </div>

        <div
          v-if="kpis.zoho_leads"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.PIPELINE_STATUS_TITLE') }}
          </h3>
          <CardAnalysisNote
            :text="report.card_analyses?.zoho_pipeline_status"
          />

          <h4 class="text-sm font-semibold text-n-slate-12 mb-2">
            {{
              t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.PIPELINE_STATUS_NEW_TITLE', {
                count: kpis.zoho_leads.new_count,
              })
            }}
          </h4>
          <table class="w-full text-sm mb-5">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.STATUS') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS') }}
                </th>
                <th class="py-1 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(count, status) in kpis.zoho_leads.by_status_new"
                :key="status"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ status }}</td>
                <td class="py-1.5 pr-3">{{ count }}</td>
                <td class="py-1.5">
                  {{ percentOf(count, kpis.zoho_leads.new_count) }}
                </td>
              </tr>
            </tbody>
          </table>

          <h4 class="text-sm font-semibold text-n-slate-12 mb-2">
            {{
              t(
                'WEEKLY_OPS_REPORTS.ZOHO_LEADS.PIPELINE_STATUS_FOLLOW_UP_TITLE',
                {
                  count: kpis.zoho_leads.follow_up_count,
                }
              )
            }}
          </h4>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.STATUS') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS') }}
                </th>
                <th class="py-1 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(count, status) in kpis.zoho_leads.by_status_follow_up"
                :key="status"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ status }}</td>
                <td class="py-1.5 pr-3">{{ count }}</td>
                <td class="py-1.5">
                  {{ percentOf(count, kpis.zoho_leads.follow_up_count) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.CONTACT_TIME.TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.contact_time" />
          <div class="h-64">
            <BarChart
              ref="contactTimeChartRef"
              :collection="contactTimeChartData"
            />
          </div>
        </div>

        <div
          v-if="kpis.contact_time_by_period_of_week"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.PERIOD_OF_WEEK.TITLE') }}
          </h3>
          <CardAnalysisNote
            :text="report.card_analyses?.contact_time_by_period"
          />
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.PERIOD_OF_WEEK.PERIOD') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE') }}
                </th>
                <th class="py-1 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr class="border-t border-n-container text-n-slate-12">
                <td class="py-1.5 pr-3">
                  {{ t('WEEKLY_OPS_REPORTS.PERIOD_OF_WEEK.WEEKDAY') }}
                </td>
                <td class="py-1.5 pr-3">
                  {{
                    `${kpis.contact_time_by_period_of_week.weekday?.first_response ?? '—'} min`
                  }}
                </td>
                <td class="py-1.5">
                  {{
                    `${kpis.contact_time_by_period_of_week.weekday?.reply_time ?? '—'} min`
                  }}
                </td>
              </tr>
              <tr class="border-t border-n-container text-n-slate-12">
                <td class="py-1.5 pr-3">
                  {{ t('WEEKLY_OPS_REPORTS.PERIOD_OF_WEEK.WEEKEND') }}
                </td>
                <td class="py-1.5 pr-3">
                  {{
                    `${kpis.contact_time_by_period_of_week.weekend?.first_response ?? '—'} min`
                  }}
                </td>
                <td class="py-1.5">
                  {{
                    `${kpis.contact_time_by_period_of_week.weekend?.reply_time ?? '—'} min`
                  }}
                </td>
              </tr>
            </tbody>
          </table>

          <template
            v-if="
              kpis.by_advisor &&
              kpis.by_advisor.some(advisor => advisor.by_period_of_week)
            "
          >
            <h4 class="text-sm font-semibold text-n-slate-12 mt-5 mb-2">
              {{ t('WEEKLY_OPS_REPORTS.PERIOD_OF_WEEK.BY_ADVISOR_TITLE') }}
            </h4>
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left text-n-slate-11">
                  <th class="py-1 pr-3 font-medium">
                    {{ t('WEEKLY_OPS_REPORTS.BY_ADVISOR.ADVISOR') }}
                  </th>
                  <th class="py-1 pr-3 font-medium">
                    {{ t('WEEKLY_OPS_REPORTS.PERIOD_OF_WEEK.WEEKDAY') }}
                  </th>
                  <th class="py-1 pr-3 font-medium">
                    {{ t('WEEKLY_OPS_REPORTS.PERIOD_OF_WEEK.WEEKEND') }}
                  </th>
                  <th class="py-1 font-medium">
                    {{
                      t(
                        'WEEKLY_OPS_REPORTS.PERIOD_OF_WEEK.CONVERSATIONS_BY_PERIOD'
                      )
                    }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="advisor in kpis.by_advisor"
                  :key="advisor.user_id"
                  class="border-t border-n-container text-n-slate-12"
                >
                  <td class="py-1.5 pr-3">{{ advisor.name }}</td>
                  <td class="py-1.5 pr-3">
                    {{
                      `${advisor.by_period_of_week?.weekday?.contact_time?.first_response ?? '—'} min`
                    }}
                  </td>
                  <td class="py-1.5 pr-3">
                    {{
                      `${advisor.by_period_of_week?.weekend?.contact_time?.first_response ?? '—'} min`
                    }}
                  </td>
                  <td class="py-1.5">
                    {{
                      `${advisor.by_period_of_week?.weekday?.conversations_count ?? 0} / ${advisor.by_period_of_week?.weekend?.conversations_count ?? 0}`
                    }}
                  </td>
                </tr>
              </tbody>
            </table>
          </template>
        </div>

        <div
          v-if="kpis.by_advisor && kpis.by_advisor.length"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.BY_ADVISOR.TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.by_advisor" />
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.BY_ADVISOR.ADVISOR') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.BY_ADVISOR.CONVERSATIONS') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE') }}
                </th>
                <th class="py-1 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="advisor in kpis.by_advisor"
                :key="advisor.user_id"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ advisor.name }}</td>
                <td class="py-1.5 pr-3">{{ advisor.conversations_count }}</td>
                <td class="py-1.5 pr-3">
                  {{ `${advisor.contact_time.first_response ?? '—'} min` }}
                </td>
                <td class="py-1.5">
                  {{ `${advisor.contact_time.reply_time ?? '—'} min` }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="conversionTotalsChartData.labels.length"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.CONVERSION_BY_OWNER.TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.conversion_totals" />
          <div class="h-64">
            <BarChart
              ref="conversionTotalsChartRef"
              :collection="conversionTotalsChartData"
            />
          </div>
        </div>

        <div
          v-if="kpis.zoho_leads"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.SOURCE_TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.zoho_source" />
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.SOURCE') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS') }}
                </th>
                <th class="py-1 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(count, source) in kpis.zoho_leads.by_source"
                :key="source"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ source }}</td>
                <td class="py-1.5 pr-3">{{ count }}</td>
                <td class="py-1.5">
                  {{ percentOf(count, kpis.zoho_leads.total) }}
                </td>
              </tr>
            </tbody>
          </table>
          <p class="text-sm text-n-slate-11 mt-3 mb-0">
            {{
              t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.QUALITY_LEADS', {
                count: kpis.zoho_leads.quality_leads_count,
                percent: kpis.zoho_leads.quality_leads_percent,
              })
            }}
          </p>
        </div>

        <div
          v-if="qualityBySourceChartData.labels.length"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.QUALITY_BY_SOURCE_TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.quality_by_source" />
          <div class="h-64">
            <BarChart
              ref="qualityBySourceChartRef"
              :collection="qualityBySourceChartData"
            />
          </div>
        </div>

        <div
          v-if="channelComparisonChartData.labels.length"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.CHANNEL_COMPARISON_TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.channel_comparison" />
          <div class="h-64">
            <BarChart
              ref="channelComparisonChartRef"
              :collection="channelComparisonChartData"
            />
          </div>
        </div>

        <div
          v-if="
            kpis.zoho_leads &&
            kpis.zoho_leads.by_owner &&
            Object.keys(kpis.zoho_leads.by_owner).length
          "
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.OWNER_TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.zoho_owner" />
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.OWNER') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS') }}
                </th>
                <th class="py-1 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(count, owner) in kpis.zoho_leads.by_owner"
                :key="owner"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ owner }}</td>
                <td class="py-1.5 pr-3">{{ count }}</td>
                <td class="py-1.5">
                  {{ percentOf(count, kpis.zoho_leads.total) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="discardReasonsTotal"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.DISCARD_TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.discard_reasons" />
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.REASON') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS') }}
                </th>
                <th class="py-1 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(count, reason) in kpis.zoho_leads.discard_reasons"
                :key="reason"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ reason }}</td>
                <td class="py-1.5 pr-3">{{ count }}</td>
                <td class="py-1.5">
                  {{ percentOf(count, discardReasonsTotal) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="kpis.schedule_distribution"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.SCHEDULE_DISTRIBUTION.TITLE') }}
          </h3>
          <CardAnalysisNote
            :text="report.card_analyses?.schedule_distribution"
          />
          <div class="grid grid-cols-2 gap-4">
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.SCHEDULE_DISTRIBUTION.WITHIN')"
              :value="String(kpis.schedule_distribution.within_business_hours)"
              :info-text="t('WEEKLY_OPS_REPORTS.SCHEDULE_DISTRIBUTION.WITHIN')"
            />
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.SCHEDULE_DISTRIBUTION.OUTSIDE')"
              :value="String(kpis.schedule_distribution.outside_business_hours)"
              :info-text="t('WEEKLY_OPS_REPORTS.SCHEDULE_DISTRIBUTION.OUTSIDE')"
            />
          </div>
        </div>

        <div
          v-if="kpis.aircall_calls"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.CALLS.TITLE') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.aircall_calls" />
          <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-5">
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.CALLS.TOTAL')"
              :value="String(kpis.aircall_calls.total)"
              :info-text="t('WEEKLY_OPS_REPORTS.CALLS.TOTAL_INFO')"
            />
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.CALLS.ANSWERED_PERCENT')"
              :value="`${kpis.aircall_calls.answered_percent}%`"
              :info-text="t('WEEKLY_OPS_REPORTS.CALLS.ANSWERED_PERCENT_INFO')"
            />
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.CALLS.AVG_DURATION')"
              :value="formatDuration(kpis.aircall_calls.avg_duration_seconds)"
              :info-text="t('WEEKLY_OPS_REPORTS.CALLS.AVG_DURATION_INFO')"
            />
            <ReportMetricCard
              :label="t('WEEKLY_OPS_REPORTS.CALLS.DIRECTION')"
              :value="`${kpis.aircall_calls.incoming} / ${kpis.aircall_calls.outgoing}`"
              :info-text="t('WEEKLY_OPS_REPORTS.CALLS.DIRECTION_INFO')"
            />
          </div>

          <template v-if="kpis.aircall_calls.by_advisor.length">
            <h4 class="text-sm font-semibold text-n-slate-12 mb-2">
              {{ t('WEEKLY_OPS_REPORTS.CALLS.BY_ADVISOR_TITLE') }}
            </h4>
            <table class="w-full text-sm">
              <thead>
                <tr class="text-left text-n-slate-11">
                  <th class="py-1 pr-3 font-medium">
                    {{ t('WEEKLY_OPS_REPORTS.CALLS.ADVISOR') }}
                  </th>
                  <th class="py-1 pr-3 font-medium">
                    {{ t('WEEKLY_OPS_REPORTS.CALLS.TOTAL_CALLS') }}
                  </th>
                  <th class="py-1 pr-3 font-medium">
                    {{ t('WEEKLY_OPS_REPORTS.CALLS.ANSWERED_PERCENT') }}
                  </th>
                  <th class="py-1 font-medium">
                    {{ t('WEEKLY_OPS_REPORTS.CALLS.AVG_DURATION_SHORT') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="advisor in kpis.aircall_calls.by_advisor"
                  :key="advisor.user_id"
                  class="border-t border-n-container text-n-slate-12"
                >
                  <td class="py-1.5 pr-3">{{ advisor.name }}</td>
                  <td class="py-1.5 pr-3">{{ advisor.total }}</td>
                  <td class="py-1.5 pr-3">{{ advisor.answered_percent }}%</td>
                  <td class="py-1.5">
                    {{ formatDuration(advisor.avg_duration_seconds) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </template>
        </div>

        <div
          v-if="
            kpis.cadences.by_status &&
            Object.keys(kpis.cadences.by_status).length
          "
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.CADENCES.BY_STATUS') }}
          </h3>
          <CardAnalysisNote :text="report.card_analyses?.cadences" />
          <div class="h-64">
            <BarChart ref="cadenceChartRef" :collection="cadenceChartData" />
          </div>
        </div>
      </template>
    </div>
  </div>
</template>
