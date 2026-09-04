<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { formatTime } from '@chatwoot/utils';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import Spinner from 'shared/components/Spinner.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import LineChart from 'shared/components/charts/LineChart.vue';

const { t } = useI18n();

const agents = useMapGetter('agents/getAgents');

const toDateInputValue = date => date.toISOString().slice(0, 10);

const filters = ref({
  since: toDateInputValue(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)),
  until: toDateInputValue(new Date()),
  desarrollo: '',
});

const isLoading = ref(false);
const report = ref(null);

const toUnixSeconds = (dateValue, endOfDay = false) => {
  const date = new Date(`${dateValue}T${endOfDay ? '23:59:59' : '00:00:00'}`);
  return Math.floor(date.getTime() / 1000).toString();
};

const isCompleteDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value);
const hasValidDateRange = computed(
  () =>
    isCompleteDate(filters.value.since) && isCompleteDate(filters.value.until)
);

const fetchReport = async () => {
  if (!hasValidDateRange.value) return;

  isLoading.value = true;
  try {
    const response = await ReportsAPI.getRevenueIntelligenceReport({
      from: toUnixSeconds(filters.value.since),
      to: toUnixSeconds(filters.value.until, true),
      desarrollo: filters.value.desarrollo || undefined,
    });
    report.value = response.data;
  } catch (error) {
    useAlert(t('REVENUE_INTELLIGENCE_REPORTS.ERRORS.FETCH'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchReport);
watch(filters, fetchReport, { deep: true });

const TABS = [
  { key: 'overview', label: t('REVENUE_INTELLIGENCE_REPORTS.TABS.OVERVIEW') },
  { key: 'funnel', label: t('REVENUE_INTELLIGENCE_REPORTS.TABS.FUNNEL') },
  {
    key: 'marketing',
    label: t('REVENUE_INTELLIGENCE_REPORTS.TABS.MARKETING'),
  },
  {
    key: 'sales_team',
    label: t('REVENUE_INTELLIGENCE_REPORTS.TABS.SALES_TEAM'),
  },
  { key: 'calls', label: t('REVENUE_INTELLIGENCE_REPORTS.TABS.CALLS') },
  {
    key: 'objections',
    label: t('REVENUE_INTELLIGENCE_REPORTS.TABS.OBJECTIONS'),
  },
  { key: 'pipeline', label: t('REVENUE_INTELLIGENCE_REPORTS.TABS.PIPELINE') },
  {
    key: 'data_quality',
    label: t('REVENUE_INTELLIGENCE_REPORTS.TABS.DATA_QUALITY'),
  },
];
const activeTab = ref('overview');
const activeTabIndex = computed(() =>
  TABS.findIndex(tab => tab.key === activeTab.value)
);
const onTabChanged = tab => {
  activeTab.value = tab.key;
};

// { desarrollo/campaign_id/agent_id/... => { metric => count } } -> filas para una tabla genérica.
const dimensionRows = dimension =>
  Object.entries(report.value?.[dimension] ?? {}).map(([id, metrics]) => ({
    id,
    metrics,
  }));

const riskSignals = category =>
  (report.value?.risk_signals?.open ?? []).filter(
    signal => signal.category === category
  );

const agentName = agentId => {
  const agent = agents.value.find(item => String(item.id) === String(agentId));
  return agent?.name || `#${agentId}`;
};

const signalSubjectLabel = signal =>
  `${signal.subject_type} #${signal.subject_id}`;

const severityBadgeClass = severity => {
  if (severity === 'high') return 'bg-n-ruby-3 text-n-ruby-11';
  if (severity === 'medium') return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-slate-3 text-n-slate-11';
};

const conversionRows = dimension =>
  Object.entries(report.value?.[dimension] ?? {}).map(([id, row]) => ({
    id,
    ...row,
  }));

const pipelineRows = computed(() =>
  Object.entries(report.value?.pipeline_stage ?? {}).map(([stage, row]) => ({
    stage,
    entered: row.entered,
    avgDurationDays: row.avg_duration_days,
  }))
);

// `campaign` llega como jerarquía anidada campaña -> adset -> advert (ver
// V2::Reports::RevenueIntelligenceBuilder#marketing_hierarchy) — se aplana aquí a una lista con
// nivel de indentación (0/1/2) para pintarla como una sola tabla con sangría, sin necesitar un
// componente de árbol nuevo. El id de campaña no tiene nombre resuelto (limitación documentada:
// esa dimensión ya tiene datos reales acumulados desde Fase 3, no se puede reescribir su clave);
// adset/advert sí traen `name` porque son dimensiones nuevas sin histórico que proteger.
const marketingRows = computed(() => {
  const campaigns = report.value?.campaign ?? [];
  const rows = [];
  campaigns.forEach(campaign => {
    rows.push({
      key: `c:${campaign.id}`,
      level: 0,
      label: campaign.id,
      metrics: campaign.metrics,
    });
    (campaign.adsets ?? []).forEach(adset => {
      rows.push({
        key: `a:${campaign.id}:${adset.id}`,
        level: 1,
        label: adset.name,
        metrics: adset.metrics,
      });
      (adset.adverts ?? []).forEach(advert => {
        rows.push({
          key: `d:${campaign.id}:${adset.id}:${advert.id}`,
          level: 2,
          label: advert.name,
          metrics: advert.metrics,
        });
      });
    });
  });
  return rows;
});

// Traduce nombres crudos del backend (event_type/signal_type/segmentos compuestos) a lenguaje de
// negocio — se aplica en TODAS las pestañas, no solo Overview, para no dejar ningún
// lead_created/cta_used:true/deal_without_lead visible tal cual en la UI.
const EVENT_TYPE_LABELS = {
  lead_created: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_CREATED'),
  lead_contacted: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_CONTACTED'),
  lead_qualified: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.LEAD_QUALIFIED'),
  deal_created: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.DEAL_CREATED'),
  appointment_created: t(
    'REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.APPOINTMENT_CREATED'
  ),
  visit_effective: t(
    'REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.VISIT_EFFECTIVE'
  ),
  reserved: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.RESERVED'),
  closed_won: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.CLOSED_WON'),
  closed_lost: t('REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.CLOSED_LOST'),
  call_started: t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.CALLS_STARTED'),
  call_answered: t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.CALLS_ANSWERED'),
  call_missed: t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.CALLS_MISSED'),
};
const eventTypeLabel = key => EVENT_TYPE_LABELS[key] || key;

const SIGNAL_TYPE_LABELS = {
  deal_stalled: t('REVENUE_INTELLIGENCE_REPORTS.SIGNAL_TYPES.DEAL_STALLED'),
  lead_no_contact: t(
    'REVENUE_INTELLIGENCE_REPORTS.SIGNAL_TYPES.LEAD_NO_CONTACT'
  ),
  appointment_no_show_unverified: t(
    'REVENUE_INTELLIGENCE_REPORTS.SIGNAL_TYPES.APPOINTMENT_NO_SHOW_UNVERIFIED'
  ),
  deal_won_stage_mismatch: t(
    'REVENUE_INTELLIGENCE_REPORTS.SIGNAL_TYPES.DEAL_WON_STAGE_MISMATCH'
  ),
  deal_lost_stage_mismatch: t(
    'REVENUE_INTELLIGENCE_REPORTS.SIGNAL_TYPES.DEAL_LOST_STAGE_MISMATCH'
  ),
  deal_without_lead: t(
    'REVENUE_INTELLIGENCE_REPORTS.SIGNAL_TYPES.DEAL_WITHOUT_LEAD'
  ),
  stage_event_gap: t(
    'REVENUE_INTELLIGENCE_REPORTS.SIGNAL_TYPES.STAGE_EVENT_GAP'
  ),
  unresolved_identity_conflict: t(
    'REVENUE_INTELLIGENCE_REPORTS.SIGNAL_TYPES.UNRESOLVED_IDENTITY_CONFLICT'
  ),
};
const signalTypeLabel = key => SIGNAL_TYPE_LABELS[key] || key;

// "Aging" del pipeline: deals estancados (signal_type deal_stalled, ya detectados por
// RevenueIntelligence::DetectRisksJob con days_stalled/stage en el context) — no requiere leer
// revenue_deals aparte, reutiliza risk_signals que el payload ya trae completo. Ordenado por más
// días estancado primero, que es la pregunta real de negocio en esta pestaña ("¿qué se está
// pudriendo en el pipeline?").
const pipelineAgingDeals = computed(() =>
  riskSignals('risk')
    .filter(signal => signal.signal_type === 'deal_stalled')
    .map(signal => ({
      id: signal.id,
      subject: signalSubjectLabel(signal),
      stage: signal.context?.stage ?? '—',
      daysStalled: signal.context?.days_stalled ?? null,
      severity: signal.severity,
    }))
    .sort((a, b) => (b.daysStalled ?? 0) - (a.daysStalled ?? 0))
);

// Score de salud de calidad de datos: derivado enteramente del conteo de señales 'data_quality'
// abiertas ya presente en el payload (risk_signals.by_category) — sin pedir nada nuevo al backend.
// Bandas deliberadamente simples (no es un cálculo estadístico, es una señal visual rápida de
// "¿hay mucho o poco que revisar ahora?").
const dataQualityHealth = computed(() => {
  const count = report.value?.risk_signals?.by_category?.data_quality ?? 0;
  if (count === 0)
    return { score: 100, label: 'GOOD', class: 'text-n-teal-11 bg-n-teal-3' };
  if (count <= 3)
    return { score: 80, label: 'FAIR', class: 'text-n-amber-11 bg-n-amber-3' };
  if (count <= 9)
    return { score: 50, label: 'POOR', class: 'text-n-amber-11 bg-n-amber-3' };
  return { score: 20, label: 'CRITICAL', class: 'text-n-ruby-11 bg-n-ruby-3' };
});

// dimension_id de call_conversion/objection_conversion trae una clave compuesta "campo:valor"
// (ej. "cta_used:true") escrita por el backend — las categorías de objeción NO son compuestas
// (ya son texto humano, ej. "financiera"), se devuelven tal cual.
const conversionSegmentLabel = dimensionId => {
  const [field, value] = dimensionId.split(':');
  if (field === 'cta_used') {
    return value === 'true'
      ? t('REVENUE_INTELLIGENCE_REPORTS.CONVERSION_SEGMENTS.CTA_USED')
      : t('REVENUE_INTELLIGENCE_REPORTS.CONVERSION_SEGMENTS.CTA_NOT_USED');
  }
  if (field === 'intent_level') {
    return t('REVENUE_INTELLIGENCE_REPORTS.CONVERSION_SEGMENTS.INTENT_LEVEL', {
      level: value,
    });
  }
  if (field === 'score_band') {
    return t('REVENUE_INTELLIGENCE_REPORTS.CONVERSION_SEGMENTS.SCORE_BAND', {
      band: value,
    });
  }
  return dimensionId;
};

// call_conversion trae 3 agrupaciones independientes en una sola lista plana (dimension_id
// compuesto "campo:valor") — se separan en 3 secciones de barras para que se lean como
// distribuciones (CTA / intención / score), no como una tabla de filas sueltas sin relación.
const CALL_CONVERSION_GROUPS = [
  {
    field: 'cta_used',
    titleKey: 'REVENUE_INTELLIGENCE_REPORTS.CALLS.GROUPS.CTA',
  },
  {
    field: 'intent_level',
    titleKey: 'REVENUE_INTELLIGENCE_REPORTS.CALLS.GROUPS.INTENT',
  },
  {
    field: 'score_band',
    titleKey: 'REVENUE_INTELLIGENCE_REPORTS.CALLS.GROUPS.SCORE',
  },
];
const callConversionGroups = computed(() => {
  const rows = conversionRows('call_conversion');
  return CALL_CONVERSION_GROUPS.map(group => ({
    field: group.field,
    title: t(group.titleKey),
    rows: rows
      .filter(row => row.id.startsWith(`${group.field}:`))
      .map(row => ({
        ...row,
        label: conversionSegmentLabel(row.id),
        barPercent: Math.min(Math.round(row.rate * 100), 100),
      })),
  })).filter(group => group.rows.length);
});

// Claves de categoría de objeción — vocabulario cerrado de
// CallAnalysis::StructuredAnalysisLlmService::OBJECTION_CATEGORIES, escrito en snake_case por el
// LLM (ej. "necesidad_alternativa") — se traduce a lenguaje de negocio aquí, igual que
// event_type/signal_type, para no dejar el snake_case crudo visible en la UI.
const OBJECTION_CATEGORY_LABELS = {
  financiera: t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.FINANCIAL'),
  producto: t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.PRODUCT'),
  ubicacion: t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.LOCATION'),
  entrega_preventa: t(
    'REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.DELIVERY_PREORDER'
  ),
  confianza: t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.TRUST'),
  necesidad_alternativa: t(
    'REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.NEED_ALTERNATIVE'
  ),
  timing: t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.TIMING'),
  autoridad: t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.AUTHORITY'),
  expectativa_fallida: t(
    'REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CATEGORIES.UNMET_EXPECTATION'
  ),
};
const objectionCategoryLabel = key => OBJECTION_CATEGORY_LABELS[key] || key;

// Barras de distribución por volumen (no por tasa, a diferencia de Calls) — la pregunta de negocio
// aquí es "¿qué objeción aparece más?", ordenado de mayor a menor frecuencia; la tasa de
// conversión se muestra como dato secundario junto a cada barra.
const objectionRows = computed(() => {
  const rows = conversionRows('objection_conversion');
  const maxTotal = Math.max(...rows.map(row => row.total), 1);
  return rows
    .map(row => ({
      ...row,
      label: objectionCategoryLabel(row.id),
      barPercent: Math.min(Math.round((row.total / maxTotal) * 100), 100),
    }))
    .sort((a, b) => b.total - a.total);
});

const formatSeconds = value =>
  value != null
    ? formatTime(value)
    : t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.NO_DATA');

const formatPct = value => `${Math.round(value * 10) / 10}%`;

// Perfil por asesor: mismas métricas de actividad de siempre (calls started/answered/missed) más
// tasa de contestada y calidad de llamada (avg_score/cta_rate, agregadas en el backend desde
// revenue_call_features) — ordenado por volumen de llamadas para que el asesor más activo
// encabece la tabla.
const salesTeamRows = computed(() =>
  dimensionRows('agent')
    .map(row => ({
      id: row.id,
      name: agentName(row.id),
      callStarted: row.metrics.call_started || 0,
      callAnswered: row.metrics.call_answered || 0,
      callMissed: row.metrics.call_missed || 0,
      answeredRate: row.metrics.call_started
        ? row.metrics.call_answered / row.metrics.call_started
        : null,
      avgScore: row.metrics.avg_score ?? null,
      ctaRate: row.metrics.cta_rate ?? null,
    }))
    .sort((a, b) => b.callStarted - a.callStarted)
);

const scoreBadgeClass = score => {
  if (score == null) return 'bg-n-slate-3 text-n-slate-11';
  if (score >= 70) return 'bg-n-teal-3 text-n-teal-11';
  if (score >= 40) return 'bg-n-amber-3 text-n-amber-11';
  return 'bg-n-ruby-3 text-n-ruby-11';
};

// ---- Overview ----

const FUNNEL_KPI_STAGES = [
  { stage: 'lead_created', labelKey: 'LEADS' },
  { stage: 'appointment_created', labelKey: 'APPOINTMENTS' },
  { stage: 'visit_effective', labelKey: 'VISITS' },
  { stage: 'reserved', labelKey: 'RESERVED' },
  { stage: 'closed_won', labelKey: 'WON' },
];

const funnelTotals = computed(
  () =>
    report.value?.funnel_totals ?? {
      lead_created: { count: 0, previous_count: 0, delta_pct: null },
    }
);
const funnelConversions = computed(
  () => report.value?.funnel_conversions ?? {}
);

const kpiCards = computed(() =>
  FUNNEL_KPI_STAGES.map(({ stage, labelKey }) => ({
    stage,
    label: t(`REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.KPI.${labelKey}`),
    ...(funnelTotals.value[stage] ?? {
      count: 0,
      previous_count: 0,
      delta_pct: null,
    }),
  }))
);

const winRate = computed(() => {
  const won = funnelTotals.value.closed_won?.count ?? 0;
  const lost = funnelTotals.value.closed_lost?.count ?? 0;
  const total = won + lost;
  return total ? Math.round((won / total) * 1000) / 10 : null;
});

const conversionMetrics = computed(() => [
  {
    label: t(
      'REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.CONVERSION.LEAD_TO_APPOINTMENT'
    ),
    value: funnelConversions.value.appointment_created,
  },
  {
    label: t(
      'REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.CONVERSION.APPOINTMENT_TO_VISIT'
    ),
    value: funnelConversions.value.visit_effective,
  },
  {
    label: t(
      'REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.CONVERSION.VISIT_TO_RESERVED'
    ),
    value: funnelConversions.value.reserved,
  },
  {
    label: t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.CONVERSION.WIN_RATE'),
    value: winRate.value != null ? winRate.value / 100 : null,
    infoText: t(
      'REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.CONVERSION.WIN_RATE_INFO'
    ),
  },
]);

// Secuencia visual del embudo — mismo orden que
// RevenueIntelligence::RefreshAggregatesJob::FUNNEL_SEQUENCE en el backend.
const FUNNEL_SEQUENCE = [
  'lead_created',
  'lead_contacted',
  'lead_qualified',
  'appointment_created',
  'visit_effective',
  'reserved',
  'closed_won',
];
const funnelSteps = computed(() =>
  FUNNEL_SEQUENCE.map(stage => ({
    stage,
    label: eventTypeLabel(stage),
    count: funnelTotals.value[stage]?.count ?? 0,
    conversion: funnelConversions.value[stage],
    deltaPct: funnelTotals.value[stage]?.delta_pct ?? null,
  }))
);

const funnelTrendChart = computed(() => {
  const trend = report.value?.funnel_trend ?? {};
  const dates = Object.keys(trend).sort();
  const metricColors = {
    lead_created: '#0ea5e9',
    appointment_created: '#7c3aed',
    closed_won: '#16a34a',
  };
  return {
    labels: dates,
    datasets: Object.keys(metricColors).map(metric => ({
      label: eventTypeLabel(metric),
      borderColor: metricColors[metric],
      backgroundColor: metricColors[metric],
      data: dates.map(date => trend[date]?.[metric] || 0),
    })),
  };
});
const trendLegend = computed(() =>
  funnelTrendChart.value.datasets.map(dataset => ({
    label: dataset.label,
    color: dataset.borderColor,
  }))
);

const journeys = computed(
  () =>
    report.value?.journeys ?? {
      avg_time_to_first_response_seconds: null,
      avg_time_to_qualification_seconds: null,
      avg_time_to_appointment_seconds: null,
      avg_time_to_close_seconds: null,
    }
);
const timeToMetrics = computed(() => [
  {
    label: t(
      'REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.AVG_TIME_TO_FIRST_RESPONSE'
    ),
    value: formatSeconds(journeys.value.avg_time_to_first_response_seconds),
  },
  {
    label: t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.AVG_TIME_TO_QUALIFICATION'),
    value: formatSeconds(journeys.value.avg_time_to_qualification_seconds),
  },
  {
    label: t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.AVG_TIME_TO_APPOINTMENT'),
    value: formatSeconds(journeys.value.avg_time_to_appointment_seconds),
  },
  {
    label: t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.AVG_TIME_TO_CLOSE'),
    value: formatSeconds(journeys.value.avg_time_to_close_seconds),
  },
]);

// Cada insight ya llega tipado {type, direction, params} desde el backend — el texto final con
// los números interpolados se arma aquí vía i18n, el backend nunca genera lenguaje natural (ver
// comentario de V2::Reports::RevenueIntelligenceBuilder#insights).
const INSIGHT_ICON = { up: '↑', down: '↓', warning: '⚠' };
const insightText = insight => {
  const key = insight.type.toUpperCase();
  return t(
    `REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.INSIGHTS.${key}`,
    insight.params
  );
};
const insights = computed(() => report.value?.insights ?? []);

// Siempre trae la lista completa de desarrollos (el backend no la filtra por el propio
// desarrollo_filter — ver V2::Reports::RevenueIntelligenceBuilder#available_desarrollos), así que
// las opciones del selector no desaparecen al elegir uno.
const availableDesarrollos = computed(
  () => report.value?.available_desarrollos ?? []
);
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <ReportHeader
        :header-title="t('REVENUE_INTELLIGENCE_REPORTS.HEADER')"
        :header-description="t('REVENUE_INTELLIGENCE_REPORTS.DESCRIPTION')"
      />

      <div class="flex flex-wrap items-end gap-3 mb-6">
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.FILTERS.SINCE') }}
          </label>
          <input
            v-model="filters.since"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.FILTERS.UNTIL') }}
          </label>
          <input
            v-model="filters.until"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.FILTERS.DESARROLLO') }}
          </label>
          <select v-model="filters.desarrollo" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.FILTERS.ALL_DESARROLLOS') }}
            </option>
            <option
              v-for="desarrollo in availableDesarrollos"
              :key="desarrollo"
              :value="desarrollo"
            >
              {{ desarrollo }}
            </option>
          </select>
        </div>
      </div>

      <div class="mb-6">
        <TabBar
          :tabs="TABS"
          :initial-active-tab="activeTabIndex"
          @tab-changed="onTabChanged"
        />
      </div>

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner />
      </div>

      <template v-else-if="report">
        <!-- Overview -->
        <template v-if="activeTab === 'overview'">
          <!-- Nivel 1: KPIs ejecutivos -->
          <div class="flex flex-wrap gap-6 mb-2">
            <div
              v-for="card in kpiCards"
              :key="card.stage"
              class="min-w-[7rem]"
            >
              <h3 class="m-0 text-sm font-medium text-n-slate-11">
                {{ card.label }}
              </h3>
              <h4 class="mt-1 mb-0 text-2xl text-n-slate-12">
                {{ card.count }}
              </h4>
              <span
                v-if="card.delta_pct != null"
                class="text-xs font-medium"
                :class="
                  card.delta_pct >= 0 ? 'text-n-teal-11' : 'text-n-ruby-11'
                "
              >
                {{ card.delta_pct >= 0 ? '↑' : '↓' }}
                {{ Math.abs(card.delta_pct) }}%
                {{
                  t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.VS_PREVIOUS_PERIOD')
                }}
              </span>
            </div>
          </div>
          <div class="flex flex-wrap gap-x-8 gap-y-1 mb-6 text-sm">
            <div v-for="metric in conversionMetrics" :key="metric.label">
              <span class="text-n-slate-11">{{ metric.label }}:</span>
              <span
                v-tooltip="metric.infoText"
                class="text-n-slate-12 font-medium ml-1"
              >
                {{ metric.value != null ? formatPct(metric.value * 100) : '—' }}
              </span>
            </div>
          </div>

          <!-- Nivel 2: Funnel + Requiere atención -->
          <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
            <div
              class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
            >
              <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
                {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.FUNNEL_TITLE') }}
              </h3>
              <div class="flex flex-col gap-2">
                <div v-for="(step, index) in funnelSteps" :key="step.stage">
                  <div class="flex items-baseline justify-between">
                    <span class="text-sm text-n-slate-11">{{
                      step.label
                    }}</span>
                    <span class="text-lg font-semibold text-n-slate-12">
                      {{ step.count }}
                    </span>
                  </div>
                  <div
                    v-if="index > 0"
                    class="text-xs text-n-slate-10 pb-2 border-b border-n-container mb-1"
                  >
                    {{ formatPct((step.conversion ?? 0) * 100) }}
                  </div>
                </div>
              </div>
            </div>

            <div
              class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
            >
              <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
                {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.RISKS_TITLE') }}
              </h3>
              <p class="text-xs text-n-slate-11 mb-4">
                {{
                  t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.RISKS_DESCRIPTION')
                }}
              </p>
              <div
                v-if="!riskSignals('risk').length"
                class="text-sm text-n-slate-11 py-4 text-center"
              >
                {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.RISKS_EMPTY') }}
              </div>
              <ul v-else class="flex flex-col gap-2">
                <li
                  v-for="signal in riskSignals('risk')"
                  :key="signal.id"
                  class="flex items-center gap-2 text-sm"
                >
                  <span
                    class="px-2 py-0.5 rounded text-xs shrink-0"
                    :class="severityBadgeClass(signal.severity)"
                  >
                    {{ signal.severity }}
                  </span>
                  <span class="text-n-slate-12">{{
                    signalTypeLabel(signal.signal_type)
                  }}</span>
                  <span class="text-n-slate-10">
                    — {{ signalSubjectLabel(signal) }}
                  </span>
                </li>
              </ul>
            </div>
          </div>

          <!-- Nivel 3: Tendencia -->
          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.TREND_TITLE') }}
            </h3>
            <div v-if="funnelTrendChart.labels.length" class="flex gap-4 mb-3">
              <div
                v-for="item in trendLegend"
                :key="item.label"
                class="flex items-center gap-1.5 text-xs text-n-slate-11"
              >
                <span
                  class="w-2.5 h-2.5 rounded-full shrink-0"
                  :style="{ backgroundColor: item.color }"
                />
                {{ item.label }}
              </div>
            </div>
            <div
              v-if="!funnelTrendChart.labels.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.TREND_EMPTY') }}
            </div>
            <div v-else class="h-56">
              <LineChart :collection="funnelTrendChart" />
            </div>
          </div>

          <!-- Nivel 4: Insights -->
          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.INSIGHTS_TITLE') }}
            </h3>
            <div
              v-if="!insights.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.INSIGHTS_EMPTY') }}
            </div>
            <ul v-else class="flex flex-col gap-2">
              <li
                v-for="insight in insights"
                :key="insight.type"
                class="flex items-start gap-2 text-sm"
              >
                <span
                  class="shrink-0"
                  :class="{
                    'text-n-teal-11': insight.direction === 'up',
                    'text-n-ruby-11': insight.direction === 'down',
                    'text-n-amber-11': insight.direction === 'warning',
                  }"
                >
                  {{ INSIGHT_ICON[insight.direction] }}
                </span>
                <span class="text-n-slate-12">{{ insightText(insight) }}</span>
              </li>
            </ul>
          </div>

          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.TIME_TO_TITLE') }}
            </h3>
            <div class="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
              <div v-for="metric in timeToMetrics" :key="metric.label">
                <div class="text-n-slate-11">{{ metric.label }}</div>
                <div class="text-n-slate-12 font-medium">
                  {{ metric.value }}
                </div>
              </div>
            </div>
          </div>
        </template>

        <!-- Funnel -->
        <template v-if="activeTab === 'funnel'">
          <div
            class="p-8 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
          >
            <h3
              class="text-base font-semibold text-n-slate-12 mt-0 mb-6 text-center"
            >
              {{ t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.FUNNEL_TITLE') }}
            </h3>
            <div class="flex flex-col items-center max-w-xs mx-auto">
              <template v-for="(step, index) in funnelSteps" :key="step.stage">
                <div class="text-center">
                  <div class="text-3xl font-bold text-n-slate-12">
                    {{ step.count }}
                  </div>
                  <div
                    class="text-xs text-n-slate-11 uppercase tracking-wide mt-1"
                  >
                    {{ step.label }}
                  </div>
                  <div
                    v-if="step.deltaPct != null"
                    class="text-xs mt-1"
                    :class="
                      step.deltaPct >= 0 ? 'text-n-teal-11' : 'text-n-ruby-11'
                    "
                  >
                    {{ step.deltaPct >= 0 ? '↑' : '↓' }}
                    {{ Math.abs(step.deltaPct) }}%
                    {{
                      t(
                        'REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.VS_PREVIOUS_PERIOD'
                      )
                    }}
                  </div>
                </div>
                <div
                  v-if="index < funnelSteps.length - 1"
                  class="flex flex-col items-center py-1.5"
                >
                  <div class="w-px h-3 bg-n-container" />
                  <div class="text-xs text-n-slate-10 font-medium py-0.5">
                    {{
                      `${(funnelSteps[index + 1].conversion ?? 0) > 1 ? '↑' : '↓'} ${formatPct((funnelSteps[index + 1].conversion ?? 0) * 100)}`
                    }}
                  </div>
                  <div class="w-px h-3 bg-n-container" />
                </div>
              </template>
            </div>
          </div>

          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.FUNNEL.TITLE') }}
            </h3>
            <div
              v-if="!dimensionRows('funnel').length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('REVENUE_INTELLIGENCE_REPORTS.FUNNEL.EMPTY') }}
            </div>
            <table v-else class="woot-table w-full">
              <thead>
                <tr>
                  <th>
                    {{ t('REVENUE_INTELLIGENCE_REPORTS.FUNNEL.DEVELOPMENT') }}
                  </th>
                  <th
                    v-for="metric in [
                      'lead_created',
                      'deal_created',
                      'appointment_created',
                      'visit_effective',
                      'reserved',
                      'closed_won',
                      'closed_lost',
                    ]"
                    :key="metric"
                  >
                    {{ eventTypeLabel(metric) }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in dimensionRows('funnel')" :key="row.id">
                  <td>{{ row.id }}</td>
                  <td
                    v-for="metric in [
                      'lead_created',
                      'deal_created',
                      'appointment_created',
                      'visit_effective',
                      'reserved',
                      'closed_won',
                      'closed_lost',
                    ]"
                    :key="metric"
                  >
                    {{ row.metrics[metric] || 0 }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>

        <!-- Marketing -->
        <div
          v-else-if="activeTab === 'marketing'"
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.TITLE') }}
          </h3>
          <div
            v-if="!marketingRows.length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.EMPTY') }}
          </div>
          <table v-else class="woot-table w-full">
            <thead>
              <tr>
                <th>
                  {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.CAMPAIGN') }}
                </th>
                <th
                  v-for="metric in ['lead_created', 'closed_won']"
                  :key="metric"
                >
                  {{ eventTypeLabel(metric) }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in marketingRows" :key="row.key">
                <td>
                  <span
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
                <td
                  v-for="metric in ['lead_created', 'closed_won']"
                  :key="metric"
                >
                  {{ row.metrics[metric] || 0 }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Sales team -->
        <div
          v-else-if="activeTab === 'sales_team'"
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.TITLE') }}
          </h3>
          <div
            v-if="!salesTeamRows.length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.EMPTY') }}
          </div>
          <table v-else class="woot-table w-full">
            <thead>
              <tr>
                <th>
                  {{ t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.AGENT') }}
                </th>
                <th>{{ eventTypeLabel('call_started') }}</th>
                <th>{{ eventTypeLabel('call_missed') }}</th>
                <th>
                  {{
                    t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.ANSWERED_RATE')
                  }}
                </th>
                <th>
                  {{ t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.AVG_SCORE') }}
                </th>
                <th>
                  {{ t('REVENUE_INTELLIGENCE_REPORTS.SALES_TEAM.CTA_RATE') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in salesTeamRows" :key="row.id">
                <td>{{ row.name }}</td>
                <td>{{ row.callStarted }}</td>
                <td>{{ row.callMissed }}</td>
                <td>
                  <div
                    v-if="row.answeredRate != null"
                    class="flex items-center gap-2"
                  >
                    <div
                      class="w-16 h-1.5 rounded-full bg-n-slate-3 overflow-hidden shrink-0"
                    >
                      <div
                        class="h-full bg-n-brand rounded-full"
                        :style="{
                          width: `${Math.min(Math.round(row.answeredRate * 100), 100)}%`,
                        }"
                      />
                    </div>
                    <span class="tabular-nums">{{
                      formatPct(row.answeredRate * 100)
                    }}</span>
                  </div>
                  <span v-else class="text-n-slate-9">{{
                    t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.NO_DATA')
                  }}</span>
                </td>
                <td>
                  <span
                    v-if="row.avgScore != null"
                    class="px-2 py-0.5 rounded text-xs font-medium tabular-nums"
                    :class="scoreBadgeClass(row.avgScore)"
                  >
                    {{ row.avgScore }}
                  </span>
                  <span v-else class="text-n-slate-9">{{
                    t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.NO_DATA')
                  }}</span>
                </td>
                <td>
                  {{
                    row.ctaRate != null
                      ? formatPct(row.ctaRate * 100)
                      : t('REVENUE_INTELLIGENCE_REPORTS.OVERVIEW.NO_DATA')
                  }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Calls -->
        <div
          v-else-if="activeTab === 'calls'"
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.CALLS.TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 mb-4">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.CALLS.DESCRIPTION') }}
          </p>
          <div
            v-if="!callConversionGroups.length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('REVENUE_INTELLIGENCE_REPORTS.CALLS.EMPTY') }}
          </div>
          <div v-else class="flex flex-col gap-6">
            <div v-for="group in callConversionGroups" :key="group.field">
              <h4
                class="text-xs font-semibold text-n-slate-11 uppercase tracking-wide mb-2"
              >
                {{ group.title }}
              </h4>
              <div class="flex flex-col gap-2.5">
                <div v-for="row in group.rows" :key="row.id">
                  <div class="flex items-center justify-between text-sm mb-1">
                    <span class="text-n-slate-12">{{ row.label }}</span>
                    <span class="text-n-slate-11 tabular-nums">
                      {{ row.converted }}/{{ row.total }}
                      <span class="text-n-slate-12 font-semibold ml-1">
                        {{ Math.round(row.rate * 1000) / 10 }}%
                      </span>
                    </span>
                  </div>
                  <div
                    class="w-full h-1.5 rounded-full bg-n-slate-3 overflow-hidden"
                  >
                    <div
                      class="h-full bg-n-brand rounded-full"
                      :style="{ width: `${row.barPercent}%` }"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- Objections -->
        <div
          v-else-if="activeTab === 'objections'"
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.TITLE') }}
          </h3>
          <div
            v-if="!objectionRows.length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.EMPTY') }}
          </div>
          <div v-else class="flex flex-col gap-2.5">
            <div v-for="row in objectionRows" :key="row.id">
              <div class="flex items-center justify-between text-sm mb-1">
                <span class="text-n-slate-12">{{ row.label }}</span>
                <span class="text-n-slate-11 tabular-nums">
                  {{
                    t('REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.MENTIONS', {
                      count: row.total,
                    })
                  }}
                  <span class="text-n-slate-12 font-semibold ml-1">
                    {{ Math.round(row.rate * 1000) / 10 }}%
                    {{
                      t(
                        'REVENUE_INTELLIGENCE_REPORTS.OBJECTIONS.CONVERTED_SUFFIX'
                      )
                    }}
                  </span>
                </span>
              </div>
              <div
                class="w-full h-1.5 rounded-full bg-n-slate-3 overflow-hidden"
              >
                <div
                  class="h-full bg-n-amber-9 rounded-full"
                  :style="{ width: `${row.barPercent}%` }"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- Pipeline -->
        <template v-if="activeTab === 'pipeline'">
          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.TITLE') }}
            </h3>
            <div
              v-if="!pipelineRows.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.EMPTY') }}
            </div>
            <table v-else class="woot-table w-full">
              <thead>
                <tr>
                  <th>
                    {{ t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.STAGE') }}
                  </th>
                  <th>
                    {{ t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.ENTERED') }}
                  </th>
                  <th>
                    {{
                      t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.AVG_DURATION')
                    }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="row in pipelineRows" :key="row.stage">
                  <td>{{ row.stage }}</td>
                  <td>{{ row.entered }}</td>
                  <td>
                    {{
                      row.avgDurationDays != null ? row.avgDurationDays : '—'
                    }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.AGING_TITLE') }}
            </h3>
            <p class="text-sm text-n-slate-11 mb-4">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.AGING_DESCRIPTION') }}
            </p>
            <div
              v-if="!pipelineAgingDeals.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.AGING_EMPTY') }}
            </div>
            <table v-else class="woot-table w-full">
              <thead>
                <tr>
                  <th>
                    {{ t('REVENUE_INTELLIGENCE_REPORTS.SIGNAL.SUBJECT') }}
                  </th>
                  <th>
                    {{ t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.STAGE') }}
                  </th>
                  <th>
                    {{
                      t('REVENUE_INTELLIGENCE_REPORTS.PIPELINE.DAYS_STALLED')
                    }}
                  </th>
                  <th>
                    {{ t('REVENUE_INTELLIGENCE_REPORTS.SIGNAL.SEVERITY') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="deal in pipelineAgingDeals" :key="deal.id">
                  <td>{{ deal.subject }}</td>
                  <td>{{ deal.stage }}</td>
                  <td>{{ deal.daysStalled ?? '—' }}</td>
                  <td>
                    <span
                      class="px-2 py-0.5 rounded text-xs"
                      :class="severityBadgeClass(deal.severity)"
                    >
                      {{ deal.severity }}
                    </span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </template>

        <!-- Data quality -->
        <div
          v-else-if="activeTab === 'data_quality'"
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <div class="flex items-center justify-between mb-1">
            <h3 class="text-base font-semibold text-n-slate-12 mt-0">
              {{ t('REVENUE_INTELLIGENCE_REPORTS.DATA_QUALITY.TITLE') }}
            </h3>
            <span
              class="px-2.5 py-1 rounded-full text-xs font-semibold"
              :class="dataQualityHealth.class"
            >
              {{
                t(
                  `REVENUE_INTELLIGENCE_REPORTS.DATA_QUALITY.HEALTH.${dataQualityHealth.label}`
                )
              }}
              ({{ dataQualityHealth.score }})
            </span>
          </div>
          <p class="text-sm text-n-slate-11 mb-4">
            {{ t('REVENUE_INTELLIGENCE_REPORTS.DATA_QUALITY.DESCRIPTION') }}
          </p>
          <div
            v-if="!riskSignals('data_quality').length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('REVENUE_INTELLIGENCE_REPORTS.DATA_QUALITY.EMPTY') }}
          </div>
          <table v-else class="woot-table w-full">
            <thead>
              <tr>
                <th>{{ t('REVENUE_INTELLIGENCE_REPORTS.SIGNAL.SEVERITY') }}</th>
                <th>{{ t('REVENUE_INTELLIGENCE_REPORTS.SIGNAL.TYPE') }}</th>
                <th>{{ t('REVENUE_INTELLIGENCE_REPORTS.SIGNAL.SUBJECT') }}</th>
                <th>{{ t('REVENUE_INTELLIGENCE_REPORTS.SIGNAL.DETECTED') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="signal in riskSignals('data_quality')"
                :key="signal.id"
              >
                <td>
                  <span
                    class="px-2 py-0.5 rounded text-xs"
                    :class="severityBadgeClass(signal.severity)"
                  >
                    {{ signal.severity }}
                  </span>
                </td>
                <td>{{ signalTypeLabel(signal.signal_type) }}</td>
                <td>{{ signalSubjectLabel(signal) }}</td>
                <td>
                  {{ new Date(signal.first_detected_at).toLocaleDateString() }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>
  </div>
</template>
