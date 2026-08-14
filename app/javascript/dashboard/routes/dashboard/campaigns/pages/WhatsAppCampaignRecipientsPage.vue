<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';

import CampaignsAPI from 'dashboard/api/campaigns';
import { downloadCsvFile } from 'dashboard/helper/downloadHelper';

import BackButton from 'dashboard/components/widgets/BackButton.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CampaignMetricsSummary from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/CampaignMetricsSummary.vue';
import CampaignRecipientsFilters from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/CampaignRecipientsFilters.vue';
import CampaignRecipientsTable from 'dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/CampaignRecipientsTable.vue';

const DEBOUNCE_DELAY = 300;
const ITEMS_PER_PAGE = 25;
const PROGRESS_POLL_INTERVAL = 15000;

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();

const campaignId = computed(() => route.params.campaignId);

const campaigns = useMapGetter('campaigns/getAllCampaigns');
const campaign = computed(() =>
  campaigns.value.find(item => String(item.id) === String(campaignId.value))
);

const metrics = ref(null);
const isFetchingMetrics = ref(false);

const recipients = ref([]);
const recipientsCount = ref(0);
const isFetchingRecipients = ref(false);
const isExporting = ref(false);

const searchValue = ref(route.query.q || '');
const statusFilter = ref(route.query.status || '');
const respondedFilter = ref(route.query.responded || '');
const pageNumber = ref(Number(route.query.page) || 1);

const buildFilterParams = () => ({
  q: searchValue.value || undefined,
  status: statusFilter.value || undefined,
  responded: respondedFilter.value || undefined,
});

const updateQuery = () => {
  const query = { ...route.query, page: String(pageNumber.value) };
  if (searchValue.value) query.q = searchValue.value;
  else delete query.q;
  if (statusFilter.value) query.status = statusFilter.value;
  else delete query.status;
  if (respondedFilter.value) query.responded = respondedFilter.value;
  else delete query.responded;
  router.replace({ query });
};

const fetchMetrics = async () => {
  isFetchingMetrics.value = true;
  try {
    const response = await CampaignsAPI.metrics(campaignId.value);
    metrics.value = response.data;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP_METRICS.API.ERROR_MESSAGE'));
  } finally {
    isFetchingMetrics.value = false;
  }
};

const fetchRecipients = async () => {
  isFetchingRecipients.value = true;
  try {
    const response = await CampaignsAPI.recipients(campaignId.value, {
      ...buildFilterParams(),
      page: pageNumber.value,
    });
    recipients.value = response.data.payload;
    recipientsCount.value = response.data.meta.count;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP_RECIPIENTS.API.ERROR_MESSAGE'));
  } finally {
    isFetchingRecipients.value = false;
  }
};

const onSearch = debounce(value => {
  searchValue.value = value;
  pageNumber.value = 1;
  updateQuery();
  fetchRecipients();
}, DEBOUNCE_DELAY);

const onStatusChange = value => {
  statusFilter.value = value;
  pageNumber.value = 1;
  updateQuery();
  fetchRecipients();
};

const onRespondedChange = value => {
  respondedFilter.value = value;
  pageNumber.value = 1;
  updateQuery();
  fetchRecipients();
};

const onPageChange = page => {
  pageNumber.value = page;
  updateQuery();
  fetchRecipients();
};

const isPausing = ref(false);
const isResuming = ref(false);

const handlePause = async () => {
  isPausing.value = true;
  try {
    await store.dispatch('campaigns/pause', campaignId.value);
    useAlert(t('CAMPAIGN.WHATSAPP_RECIPIENTS.PAUSE.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP_RECIPIENTS.PAUSE.ERROR_MESSAGE'));
  } finally {
    isPausing.value = false;
  }
};

const handleResume = async () => {
  isResuming.value = true;
  try {
    await store.dispatch('campaigns/resume', campaignId.value);
    useAlert(t('CAMPAIGN.WHATSAPP_RECIPIENTS.RESUME.SUCCESS_MESSAGE'));
    fetchMetrics();
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP_RECIPIENTS.RESUME.ERROR_MESSAGE'));
  } finally {
    isResuming.value = false;
  }
};

const handleExport = async () => {
  isExporting.value = true;
  try {
    const response = await CampaignsAPI.exportRecipients(
      campaignId.value,
      buildFilterParams()
    );
    downloadCsvFile(
      `${campaign.value?.title || 'campana'}-destinatarios.csv`,
      response.data
    );
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP_RECIPIENTS.EXPORT.ERROR_MESSAGE'));
  } finally {
    isExporting.value = false;
  }
};

let progressInterval = null;

const syncProgressPolling = () => {
  clearInterval(progressInterval);
  progressInterval = null;
  if (campaign.value?.campaign_status === 'processing') {
    progressInterval = setInterval(fetchMetrics, PROGRESS_POLL_INTERVAL);
  }
};

watch(() => campaign.value?.campaign_status, syncProgressPolling);

onMounted(async () => {
  if (!campaigns.value.length) {
    await store.dispatch('campaigns/get');
  }
  fetchMetrics();
  fetchRecipients();
  syncProgressPolling();
});

onBeforeUnmount(() => {
  clearInterval(progressInterval);
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6 pt-6">
      <div
        class="flex flex-col w-full max-w-5xl gap-3 pb-4 mx-auto border-b border-n-weak"
      >
        <BackButton
          compact
          :back-url="{ name: 'campaigns_whatsapp_index' }"
          :button-label="t('CAMPAIGN.WHATSAPP_RECIPIENTS.BACK_TO_CAMPAIGNS')"
        />
        <div class="flex items-center justify-between gap-2">
          <span class="text-heading-1 text-n-slate-12 line-clamp-1">
            {{ campaign?.title || t('CAMPAIGN.WHATSAPP_RECIPIENTS.TITLE') }}
          </span>
          <div class="flex items-center gap-2">
            <Button
              v-if="campaign?.campaign_status === 'processing'"
              :label="t('CAMPAIGN.WHATSAPP_RECIPIENTS.PAUSE.LABEL')"
              icon="i-lucide-pause"
              variant="faded"
              color="amber"
              size="sm"
              :is-loading="isPausing"
              @click="handlePause"
            />
            <Button
              v-else-if="campaign?.campaign_status === 'paused'"
              :label="t('CAMPAIGN.WHATSAPP_RECIPIENTS.RESUME.LABEL')"
              icon="i-lucide-play"
              variant="faded"
              color="teal"
              size="sm"
              :is-loading="isResuming"
              @click="handleResume"
            />
            <Button
              :label="t('CAMPAIGN.WHATSAPP_RECIPIENTS.EXPORT.LABEL')"
              icon="i-lucide-download"
              variant="faded"
              color="slate"
              size="sm"
              :is-loading="isExporting"
              @click="handleExport"
            />
          </div>
        </div>
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="flex flex-col w-full max-w-5xl gap-6 py-4 mx-auto">
        <div
          v-if="isFetchingMetrics"
          class="flex items-center justify-center py-6"
        >
          <Spinner />
        </div>
        <CampaignMetricsSummary v-else-if="metrics" :metrics="metrics" />

        <CampaignRecipientsFilters
          :search-value="searchValue"
          :status-filter="statusFilter"
          :responded-filter="respondedFilter"
          @search="onSearch"
          @update:status="onStatusChange"
          @update:responded="onRespondedChange"
        />

        <CampaignRecipientsTable
          :recipients="recipients"
          :is-fetching="isFetchingRecipients"
          :current-page="pageNumber"
          :total-items="recipientsCount"
          :items-per-page="ITEMS_PER_PAGE"
          @update:current-page="onPageChange"
        />
      </div>
    </main>
  </section>
</template>
