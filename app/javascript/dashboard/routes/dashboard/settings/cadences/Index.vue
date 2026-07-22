<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import CadencesAPI from 'dashboard/api/cadences';
import ReportHeader from '../reports/components/ReportHeader.vue';
import ReportMetricCard from '../reports/components/ReportMetricCard.vue';
import Spinner from 'shared/components/Spinner.vue';
import CadenceFilters from './components/CadenceFilters.vue';
import CadenceVariantsTable from './components/CadenceVariantsTable.vue';
import CadenceStepsTable from './components/CadenceStepsTable.vue';
import CadenceAgentsTable from './components/CadenceAgentsTable.vue';
import CadenceTemplatesTable from './components/CadenceTemplatesTable.vue';
import CadenceActiveLeadsTable from './components/CadenceActiveLeadsTable.vue';
import EnrollConversationModal from './components/EnrollConversationModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const TABS = ['summary', 'active_leads'];
const activeTab = ref('summary');

const filters = ref({
  inbox_id: '',
  assignee_id: '',
  team_id: '',
  status: '',
  step: '',
  since: '',
  until: '',
});

const isLoading = ref(false);
const summary = ref(null);
const variants = ref([]);
const steps = ref([]);
const agentsMetrics = ref([]);
const templates = ref([]);
const activeLeads = ref([]);
const enrollModalRef = ref(null);
const inboxes = useMapGetter('inboxes/getInboxes');
const showEnrollPastLeadsConfirmation = ref(false);

const selectedInboxName = computed(() => {
  const inbox = inboxes.value.find(i => i.id === filters.value.inbox_id);
  return inbox ? inbox.name : null;
});

const queryParams = computed(() => {
  const params = {};
  Object.entries(filters.value).forEach(([key, value]) => {
    if (value !== '' && value !== null && value !== undefined) {
      params[key] = value;
    }
  });
  return params;
});

const formatSeconds = seconds => {
  if (!seconds) return '0m';
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  return `${Math.round(minutes / 60)}h`;
};

const kpiCards = computed(() => {
  if (!summary.value) return [];
  const s = summary.value;
  return [
    {
      key: 'leads_in_cadence',
      label: t('CADENCE.KPI.LEADS_IN_CADENCE'),
      value: String(s.leads_in_cadence),
    },
    {
      key: 'response_rate',
      label: t('CADENCE.KPI.RESPONSE_RATE'),
      value: `${s.response_rate}%`,
    },
    {
      key: 'no_response_rate',
      label: t('CADENCE.KPI.NO_RESPONSE_RATE'),
      value: `${s.no_response_rate}%`,
    },
    {
      key: 'call_tasks_created',
      label: t('CADENCE.KPI.CALL_TASKS_CREATED'),
      value: String(s.call_tasks_created),
    },
    {
      key: 'calls_completed',
      label: t('CADENCE.KPI.CALLS_COMPLETED'),
      value: String(s.calls_completed),
    },
    {
      key: 'call_compliance_rate',
      label: t('CADENCE.KPI.CALL_COMPLIANCE_RATE'),
      value: `${s.call_compliance_rate}%`,
    },
    {
      key: 'avg_lead_response_time',
      label: t('CADENCE.KPI.AVG_LEAD_RESPONSE_TIME'),
      value: formatSeconds(s.avg_lead_response_time_seconds),
    },
    {
      key: 'avg_agent_action_time',
      label: t('CADENCE.KPI.AVG_AGENT_ACTION_TIME'),
      value: formatSeconds(s.avg_agent_action_time_seconds),
    },
    {
      key: 'recovered_count',
      label: t('CADENCE.KPI.RECOVERED'),
      value: String(s.recovered_count),
    },
    {
      key: 'cold_count',
      label: t('CADENCE.KPI.COLD'),
      value: String(s.cold_count),
    },
  ];
});

const fetchAnalytics = async () => {
  isLoading.value = true;
  try {
    const [summaryRes, variantsRes, stepsRes, agentsRes, templatesRes] =
      await Promise.all([
        CadencesAPI.analyticsSummary(queryParams.value),
        CadencesAPI.analyticsVariants(queryParams.value),
        CadencesAPI.analyticsSteps(queryParams.value),
        CadencesAPI.analyticsAgents(queryParams.value),
        CadencesAPI.analyticsTemplates(queryParams.value),
      ]);
    summary.value = summaryRes.data;
    variants.value = variantsRes.data;
    steps.value = stepsRes.data;
    agentsMetrics.value = agentsRes.data;
    templates.value = templatesRes.data;
  } catch (error) {
    useAlert(t('CADENCE.ERRORS.FETCH_ANALYTICS'));
  } finally {
    isLoading.value = false;
  }
};

const fetchActiveLeads = async () => {
  isLoading.value = true;
  try {
    const { data } = await CadencesAPI.get(queryParams.value);
    activeLeads.value = data;
  } catch (error) {
    useAlert(t('CADENCE.ERRORS.FETCH_LEADS'));
  } finally {
    isLoading.value = false;
  }
};

const refresh = () => {
  if (activeTab.value === 'summary') {
    fetchAnalytics();
  } else {
    fetchActiveLeads();
  }
};

const onPause = async id => {
  await CadencesAPI.pause(id);
  fetchActiveLeads();
};

const onResume = async id => {
  await CadencesAPI.resume(id);
  fetchActiveLeads();
};

const onCancel = async id => {
  await CadencesAPI.cancel(id);
  fetchActiveLeads();
};

const onEnrolled = () => {
  fetchActiveLeads();
};

const closeEnrollPastLeadsConfirmation = () => {
  showEnrollPastLeadsConfirmation.value = false;
};

const confirmEnrollPastLeads = async () => {
  const inboxId = filters.value.inbox_id || null;
  closeEnrollPastLeadsConfirmation();
  try {
    await CadencesAPI.enrollPastLeads(inboxId);
    useAlert(t('CADENCE.ENROLL_PAST_LEADS.SUCCESS'));
  } catch (error) {
    useAlert(t('CADENCE.ENROLL_PAST_LEADS.ERROR'));
  }
};

onMounted(refresh);
watch(filters, refresh, { deep: true });
watch(activeTab, refresh);
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <ReportHeader :header-title="t('CADENCE.TITLE')" />

      <div
        class="flex items-center justify-between border-b border-n-weak mb-4"
      >
        <div class="flex gap-4">
          <button
            v-for="tab in TABS"
            :key="tab"
            class="pb-2 text-sm border-b-2 -mb-px"
            :class="
              activeTab === tab
                ? 'border-n-blue-9 text-n-slate-12 font-medium'
                : 'border-transparent text-n-slate-11'
            "
            @click="activeTab = tab"
          >
            {{
              t(
                `CADENCE.TABS.${tab === 'summary' ? 'SUMMARY' : 'ACTIVE_LEADS'}`
              )
            }}
          </button>
        </div>
        <div v-if="activeTab === 'active_leads'" class="flex gap-2 mb-2">
          <Button
            :label="t('CADENCE.ENROLL_PAST_LEADS.OPEN_BUTTON')"
            size="sm"
            faded
            @click="showEnrollPastLeadsConfirmation = true"
          />
          <Button
            :label="t('CADENCE.ENROLL_MODAL.OPEN_BUTTON')"
            size="sm"
            @click="enrollModalRef?.open()"
          />
        </div>
      </div>

      <CadenceFilters v-model="filters" />

      <EnrollConversationModal ref="enrollModalRef" @enrolled="onEnrolled" />

      <woot-delete-modal
        v-model:show="showEnrollPastLeadsConfirmation"
        :on-close="closeEnrollPastLeadsConfirmation"
        :on-confirm="confirmEnrollPastLeads"
        :title="t('CADENCE.ENROLL_PAST_LEADS.CONFIRM_TITLE')"
        :message="
          selectedInboxName
            ? t('CADENCE.ENROLL_PAST_LEADS.CONFIRM_MESSAGE_INBOX', {
                inbox: selectedInboxName,
              })
            : t('CADENCE.ENROLL_PAST_LEADS.CONFIRM_MESSAGE_ALL')
        "
        :confirm-text="t('CADENCE.ENROLL_PAST_LEADS.CONFIRM_YES')"
        :reject-text="t('CADENCE.ENROLL_PAST_LEADS.CONFIRM_NO')"
      />

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner />
      </div>

      <template v-else-if="activeTab === 'summary'">
        <div class="grid grid-cols-2 md:grid-cols-5 gap-4 mb-8">
          <ReportMetricCard
            v-for="card in kpiCards"
            :key="card.key"
            :label="card.label"
            :value="card.value"
            :info-text="card.label"
          />
        </div>

        <CadenceVariantsTable :variants="variants" />
        <CadenceStepsTable :steps="steps" />
        <CadenceAgentsTable :agents="agentsMetrics" />
        <CadenceTemplatesTable :templates="templates" />
      </template>

      <CadenceActiveLeadsTable
        v-else
        :leads="activeLeads"
        @pause="onPause"
        @resume="onResume"
        @cancel="onCancel"
      />
    </div>
  </div>
</template>
