<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import ReportsAPI from 'dashboard/api/reports';
import CallAnalysesAPI from 'dashboard/api/callAnalyses';
import ReportHeader from './components/ReportHeader.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import LineChart from 'shared/components/charts/LineChart.vue';
import CallAnalysisDetailModal from './components/CallAnalysisDetailModal.vue';

const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');
const agents = useMapGetter('agents/getAgents');

const toDateInputValue = date => date.toISOString().slice(0, 10);

const filters = ref({
  since: toDateInputValue(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)),
  until: toDateInputValue(new Date()),
  inboxId: '',
  agentId: '',
  confidence: '',
  conversationType: '',
});

const CONVERSATION_TYPES = [
  'prospeccion_inicial',
  'seguimiento_pre_cita',
  'confirmacion_cita',
  'post_visita',
  'reactivacion',
];
const CONFIDENCE_LEVELS = ['high', 'medium', 'low'];

const isLoading = ref(false);
const agentReport = ref(null);
const projectReport = ref(null);

const isQueueLoading = ref(false);
const reviewQueue = ref([]);
const retryingId = ref(null);

const isRecentLoading = ref(false);
const recentCalls = ref([]);
const recentCallsMeta = ref({ currentPage: 1, totalPages: 1, totalCount: 0 });
const recentCallsPage = ref(1);
const detailModalRef = ref(null);

const toUnixSeconds = (dateValue, endOfDay = false) => {
  const date = new Date(`${dateValue}T${endOfDay ? '23:59:59' : '00:00:00'}`);
  return Math.floor(date.getTime() / 1000).toString();
};

const isCompleteDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value);
const hasValidDateRange = computed(
  () =>
    isCompleteDate(filters.value.since) && isCompleteDate(filters.value.until)
);

const fetchReports = async () => {
  if (!hasValidDateRange.value) return;

  isLoading.value = true;
  try {
    const from = toUnixSeconds(filters.value.since);
    const to = toUnixSeconds(filters.value.until, true);

    const [agentsResponse, projectResponse] = await Promise.all([
      ReportsAPI.getCallIntelligenceAgentsReport({
        from,
        to,
        agentId: filters.value.agentId || undefined,
        confidence: filters.value.confidence || undefined,
        conversationType: filters.value.conversationType || undefined,
      }),
      filters.value.inboxId
        ? ReportsAPI.getCallIntelligenceProjectReport({
            from,
            to,
            inboxId: filters.value.inboxId,
          })
        : Promise.resolve(null),
    ]);

    agentReport.value = agentsResponse.data;
    projectReport.value = projectResponse?.data ?? null;
  } catch (error) {
    useAlert(t('CALL_INTELLIGENCE_REPORTS.ERRORS.FETCH'));
  } finally {
    isLoading.value = false;
  }
};

const fetchReviewQueue = async () => {
  isQueueLoading.value = true;
  try {
    const response = await CallAnalysesAPI.getNeedsReview();
    reviewQueue.value = response.data;
  } catch (error) {
    useAlert(t('CALL_INTELLIGENCE_REPORTS.ERRORS.FETCH_QUEUE'));
  } finally {
    isQueueLoading.value = false;
  }
};

const fetchRecentCalls = async () => {
  if (!hasValidDateRange.value) return;

  isRecentLoading.value = true;
  try {
    const response = await CallAnalysesAPI.getRecent({
      since: toUnixSeconds(filters.value.since),
      until: toUnixSeconds(filters.value.until, true),
      agentId: filters.value.agentId || undefined,
      inboxId: filters.value.inboxId || undefined,
      confidence: filters.value.confidence || undefined,
      conversationType: filters.value.conversationType || undefined,
      page: recentCallsPage.value,
    });
    recentCalls.value = response.data.payload;
    recentCallsMeta.value = {
      currentPage: response.data.meta.current_page,
      totalPages: response.data.meta.total_pages,
      totalCount: response.data.meta.total_count,
    };
  } catch (error) {
    useAlert(t('CALL_INTELLIGENCE_REPORTS.ERRORS.FETCH_RECENT'));
  } finally {
    isRecentLoading.value = false;
  }
};

const goToRecentCallsPage = page => {
  recentCallsPage.value = page;
};

const openDetail = callAnalysisId => {
  detailModalRef.value?.open(callAnalysisId);
};

onMounted(() => {
  fetchReports();
  fetchReviewQueue();
  fetchRecentCalls();
});
watch(filters, fetchReports, { deep: true });
watch(
  filters,
  () => {
    if (recentCallsPage.value === 1) {
      fetchRecentCalls();
    } else {
      recentCallsPage.value = 1;
    }
  },
  { deep: true }
);
watch(recentCallsPage, fetchRecentCalls);

const agentRows = computed(() => agentReport.value?.agents ?? []);

const callsAnalyzed = computed(() =>
  agentRows.value.reduce((sum, row) => sum + row.calls_analyzed, 0)
);

const averageScore = computed(() => {
  const withScore = agentRows.value.filter(row => row.average_score != null);
  if (!withScore.length) return null;

  const weightedTotal = withScore.reduce(
    (sum, row) => sum + row.average_score * row.calls_analyzed,
    0
  );
  const totalCalls = withScore.reduce(
    (sum, row) => sum + row.calls_analyzed,
    0
  );
  return totalCalls ? Math.round((weightedTotal / totalCalls) * 10) / 10 : null;
});

const topConversationType = row => {
  const distribution = row.conversation_type_distribution || {};
  const [topType] = Object.entries(distribution).sort((a, b) => b[1] - a[1]);
  return topType ? topType[0] : '—';
};

const chartFromTally = tally => ({
  labels: Object.keys(tally || {}),
  datasets: [
    {
      backgroundColor: '#7c3aed',
      data: Object.values(tally || {}),
    },
  ],
});

const objectionsChart = computed(() =>
  chartFromTally(agentReport.value?.objections_tally)
);
const risksChart = computed(() =>
  chartFromTally(agentReport.value?.risks_tally)
);
const conversationTypeChart = computed(() =>
  chartFromTally(agentReport.value?.conversation_type_tally)
);
const confidenceChart = computed(() =>
  chartFromTally(agentReport.value?.confidence_tally)
);
const scoreReadingChart = computed(() =>
  chartFromTally(agentReport.value?.score_reading_tally)
);

const scoreEvolutionChart = computed(() => {
  const evolution = agentReport.value?.score_evolution || {};
  return {
    labels: Object.keys(evolution),
    datasets: [
      {
        borderColor: '#7c3aed',
        backgroundColor: '#7c3aed',
        data: Object.values(evolution),
      },
    ],
  };
});

const projectLossReasons = computed(
  () =>
    projectReport.value?.loss_reasons ?? {
      total_sin_avance: 0,
      by_top_objection: {},
    }
);
const projectCrmMismatch = computed(
  () => projectReport.value?.crm_vs_conversation_mismatch ?? {}
);

const agentName = agentId => {
  const agent = agents.value.find(item => item.id === agentId);
  return agent?.name || '—';
};

const inboxName = inboxId => {
  const inbox = inboxes.value.find(item => item.id === inboxId);
  return inbox?.name || '—';
};

const retryAnalysis = async record => {
  retryingId.value = record.id;
  try {
    await CallAnalysesAPI.retry(record.id);
    useAlert(t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.RETRY_SUCCESS'));
    await fetchReviewQueue();
  } catch (error) {
    useAlert(t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.RETRY_ERROR'));
  } finally {
    retryingId.value = null;
  }
};
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <ReportHeader
        :header-title="t('CALL_INTELLIGENCE_REPORTS.HEADER')"
        :header-description="t('CALL_INTELLIGENCE_REPORTS.DESCRIPTION')"
      />

      <div class="flex flex-wrap items-end gap-3 mb-6">
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.SINCE') }}
          </label>
          <input
            v-model="filters.since"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.UNTIL') }}
          </label>
          <input
            v-model="filters.until"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.INBOX') }}
          </label>
          <select v-model="filters.inboxId" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.ALL_INBOXES') }}
            </option>
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.AGENT') }}
          </label>
          <select v-model="filters.agentId" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.ALL_AGENTS') }}
            </option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.CONFIDENCE') }}
          </label>
          <select v-model="filters.confidence" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.ALL_CONFIDENCE') }}
            </option>
            <option
              v-for="level in CONFIDENCE_LEVELS"
              :key="level"
              :value="level"
            >
              {{ level }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('CALL_INTELLIGENCE_REPORTS.FILTERS.CONVERSATION_TYPE') }}
          </label>
          <select v-model="filters.conversationType" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{
                t('CALL_INTELLIGENCE_REPORTS.FILTERS.ALL_CONVERSATION_TYPES')
              }}
            </option>
            <option
              v-for="type in CONVERSATION_TYPES"
              :key="type"
              :value="type"
            >
              {{ type }}
            </option>
          </select>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner />
      </div>

      <template v-else>
        <div class="flex flex-wrap gap-6 mb-6">
          <ReportMetricCard
            :label="t('CALL_INTELLIGENCE_REPORTS.SUMMARY.CALLS_ANALYZED')"
            :value="String(callsAnalyzed)"
            :info-text="
              t('CALL_INTELLIGENCE_REPORTS.SUMMARY.CALLS_ANALYZED_INFO')
            "
          />
          <ReportMetricCard
            :label="t('CALL_INTELLIGENCE_REPORTS.SUMMARY.AVERAGE_SCORE')"
            :value="averageScore != null ? String(averageScore) : '—'"
            :info-text="
              t('CALL_INTELLIGENCE_REPORTS.SUMMARY.AVERAGE_SCORE_INFO')
            "
          />
        </div>

        <div
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
            {{ t('CALL_INTELLIGENCE_REPORTS.AGENTS_TABLE.TITLE') }}
          </h3>
          <div
            v-if="!agentRows.length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('CALL_INTELLIGENCE_REPORTS.AGENTS_TABLE.EMPTY') }}
          </div>
          <table v-else class="woot-table w-full">
            <thead>
              <tr>
                <th>{{ t('CALL_INTELLIGENCE_REPORTS.AGENTS_TABLE.AGENT') }}</th>
                <th>{{ t('CALL_INTELLIGENCE_REPORTS.AGENTS_TABLE.CALLS') }}</th>
                <th>
                  {{ t('CALL_INTELLIGENCE_REPORTS.AGENTS_TABLE.VOICEMAIL') }}
                </th>
                <th>
                  {{
                    t('CALL_INTELLIGENCE_REPORTS.AGENTS_TABLE.AVERAGE_SCORE')
                  }}
                </th>
                <th>
                  {{ t('CALL_INTELLIGENCE_REPORTS.AGENTS_TABLE.TOP_TYPE') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="row in agentRows" :key="row.agent_id">
                <td>{{ row.agent_name || agentName(row.agent_id) }}</td>
                <td>{{ row.calls_analyzed }}</td>
                <td>
                  {{ row.voicemail_count }} ({{ row.voicemail_percent }}%)
                </td>
                <td>
                  {{
                    row.average_score != null
                      ? row.average_score
                      : t(
                          'CALL_INTELLIGENCE_REPORTS.AGENTS_TABLE.NO_REAL_CALLS'
                        )
                  }}
                </td>
                <td>{{ topConversationType(row) }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('CALL_INTELLIGENCE_REPORTS.OBJECTIONS_CHART.TITLE') }}
            </h3>
            <div
              v-if="!objectionsChart.labels.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('CALL_INTELLIGENCE_REPORTS.OBJECTIONS_CHART.EMPTY') }}
            </div>
            <div v-else class="h-56">
              <BarChart :collection="objectionsChart" />
            </div>
          </div>

          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('CALL_INTELLIGENCE_REPORTS.RISKS_CHART.TITLE') }}
            </h3>
            <div
              v-if="!risksChart.labels.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('CALL_INTELLIGENCE_REPORTS.RISKS_CHART.EMPTY') }}
            </div>
            <div v-else class="h-56">
              <BarChart :collection="risksChart" />
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-6">
          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('CALL_INTELLIGENCE_REPORTS.TYPE_CHART.TITLE') }}
            </h3>
            <div
              v-if="!conversationTypeChart.labels.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('CALL_INTELLIGENCE_REPORTS.TYPE_CHART.EMPTY') }}
            </div>
            <div v-else class="h-56">
              <BarChart :collection="conversationTypeChart" />
            </div>
          </div>

          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('CALL_INTELLIGENCE_REPORTS.CONFIDENCE_CHART.TITLE') }}
            </h3>
            <div
              v-if="!confidenceChart.labels.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('CALL_INTELLIGENCE_REPORTS.CONFIDENCE_CHART.EMPTY') }}
            </div>
            <div v-else class="h-56">
              <BarChart :collection="confidenceChart" />
            </div>
          </div>

          <div
            class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
          >
            <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
              {{ t('CALL_INTELLIGENCE_REPORTS.SCORE_READING_CHART.TITLE') }}
            </h3>
            <div
              v-if="!scoreReadingChart.labels.length"
              class="text-sm text-n-slate-11 py-4 text-center"
            >
              {{ t('CALL_INTELLIGENCE_REPORTS.SCORE_READING_CHART.EMPTY') }}
            </div>
            <div v-else class="h-56">
              <BarChart :collection="scoreReadingChart" />
            </div>
          </div>
        </div>

        <div
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-4">
            {{ t('CALL_INTELLIGENCE_REPORTS.SCORE_EVOLUTION_CHART.TITLE') }}
          </h3>
          <div
            v-if="!scoreEvolutionChart.labels.length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('CALL_INTELLIGENCE_REPORTS.SCORE_EVOLUTION_CHART.EMPTY') }}
          </div>
          <div v-else class="h-56">
            <LineChart :collection="scoreEvolutionChart" />
          </div>
        </div>

        <div
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
            {{ t('CALL_INTELLIGENCE_REPORTS.PROJECT.TITLE') }}
          </h3>
          <p v-if="!filters.inboxId" class="text-sm text-n-slate-11">
            {{ t('CALL_INTELLIGENCE_REPORTS.PROJECT.SELECT_INBOX_HINT') }}
          </p>
          <template v-else-if="projectReport">
            <div class="mt-3">
              <h4 class="text-sm font-medium text-n-slate-12 mb-2">
                {{ t('CALL_INTELLIGENCE_REPORTS.PROJECT.LOSS_REASONS_TITLE') }}
              </h4>
              <p class="text-sm text-n-slate-11">
                {{
                  t('CALL_INTELLIGENCE_REPORTS.PROJECT.LOSS_REASONS_TOTAL', {
                    count: projectLossReasons.total_sin_avance,
                  })
                }}
              </p>
              <ul class="list-disc pl-5 text-sm text-n-slate-11">
                <li
                  v-for="(
                    count, category
                  ) in projectLossReasons.by_top_objection"
                  :key="category"
                >
                  {{ category }}: {{ count }}
                </li>
              </ul>
            </div>

            <div class="mt-4">
              <h4 class="text-sm font-medium text-n-slate-12 mb-2">
                {{ t('CALL_INTELLIGENCE_REPORTS.PROJECT.CRM_MISMATCH_TITLE') }}
              </h4>
              <div
                v-if="!Object.keys(projectCrmMismatch).length"
                class="text-sm text-n-slate-11"
              >
                {{ t('CALL_INTELLIGENCE_REPORTS.PROJECT.CRM_MISMATCH_EMPTY') }}
              </div>
              <ul v-else class="list-disc pl-5 text-sm text-n-slate-11">
                <li v-for="(count, stage) in projectCrmMismatch" :key="stage">
                  {{ stage }}: {{ count }}
                </li>
              </ul>
            </div>
          </template>
        </div>

        <div
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
            {{ t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 mb-4">
            {{ t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.DESCRIPTION') }}
          </p>

          <div v-if="isRecentLoading" class="flex justify-center py-4">
            <Spinner />
          </div>
          <div
            v-else-if="!recentCalls.length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.EMPTY') }}
          </div>
          <table v-else class="woot-table w-full">
            <thead>
              <tr>
                <th>{{ t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.CALL') }}</th>
                <th>{{ t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.AGENT') }}</th>
                <th>{{ t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.TYPE') }}</th>
                <th>
                  {{ t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.CONFIDENCE') }}
                </th>
                <th>{{ t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.SCORE') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="record in recentCalls"
                :key="record.id"
                class="cursor-pointer hover:bg-n-alpha-1"
                @click="openDetail(record.id)"
              >
                <td>
                  #{{ record.call_id }} — {{ inboxName(record.inbox_id) }}
                </td>
                <td>{{ record.agent_name || agentName(record.agent_id) }}</td>
                <td>{{ record.conversation_type }}</td>
                <td>{{ record.confidence }}</td>
                <td>{{ record.total_score ?? '—' }}</td>
              </tr>
            </tbody>
          </table>

          <div
            v-if="recentCalls.length"
            class="flex items-center justify-between mt-3 text-sm text-n-slate-11"
          >
            <span>
              {{
                t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.TOTAL_COUNT', {
                  count: recentCallsMeta.totalCount,
                })
              }}
            </span>
            <div class="flex items-center gap-2">
              <Button
                size="sm"
                variant="outline"
                :disabled="recentCallsMeta.currentPage <= 1"
                :label="t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.PREVIOUS')"
                @click="goToRecentCallsPage(recentCallsMeta.currentPage - 1)"
              />
              <span>
                {{
                  t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.PAGE_OF', {
                    current: recentCallsMeta.currentPage,
                    total: recentCallsMeta.totalPages,
                  })
                }}
              </span>
              <Button
                size="sm"
                variant="outline"
                :disabled="
                  recentCallsMeta.currentPage >= recentCallsMeta.totalPages
                "
                :label="t('CALL_INTELLIGENCE_REPORTS.RECENT_CALLS.NEXT')"
                @click="goToRecentCallsPage(recentCallsMeta.currentPage + 1)"
              />
            </div>
          </div>
        </div>

        <div
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
            {{ t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 mb-4">
            {{ t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.DESCRIPTION') }}
          </p>

          <div v-if="isQueueLoading" class="flex justify-center py-4">
            <Spinner />
          </div>
          <div
            v-else-if="!reviewQueue.length"
            class="text-sm text-n-slate-11 py-4 text-center"
          >
            {{ t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.EMPTY') }}
          </div>
          <table v-else class="woot-table w-full">
            <thead>
              <tr>
                <th>
                  {{ t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.COLUMNS.CALL') }}
                </th>
                <th>
                  {{ t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.COLUMNS.STEP') }}
                </th>
                <th>
                  {{
                    t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.COLUMNS.ATTEMPTS')
                  }}
                </th>
                <th>
                  {{
                    t(
                      'CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.COLUMNS.LAST_ATTEMPT'
                    )
                  }}
                </th>
                <th />
              </tr>
            </thead>
            <tbody>
              <tr v-for="record in reviewQueue" :key="record.id">
                <td>
                  #{{ record.call_id }} — {{ inboxName(record.inbox_id) }}
                </td>
                <td>{{ record.error_step || record.status }}</td>
                <td>{{ record.attempts }}</td>
                <td>{{ record.last_attempted_at }}</td>
                <td>
                  <Button
                    size="sm"
                    variant="outline"
                    :is-loading="retryingId === record.id"
                    :label="t('CALL_INTELLIGENCE_REPORTS.REVIEW_QUEUE.RETRY')"
                    @click="retryAnalysis(record)"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>

    <CallAnalysisDetailModal ref="detailModalRef" />
  </div>
</template>
