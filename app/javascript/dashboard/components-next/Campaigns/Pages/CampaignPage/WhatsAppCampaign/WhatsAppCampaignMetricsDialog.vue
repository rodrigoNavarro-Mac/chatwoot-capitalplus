<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import CampaignsAPI from 'dashboard/api/campaigns';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ReportMetricCard from 'dashboard/routes/dashboard/settings/reports/components/ReportMetricCard.vue';

const props = defineProps({
  selectedCampaign: {
    type: Object,
    default: null,
  },
});

const { t } = useI18n();

const dialogRef = ref(null);
const isFetching = ref(false);
const metrics = ref(null);

const formatCount = value => (value ?? 0).toLocaleString();
const formatPercent = value => `${value ?? 0}%`;

const fetchMetrics = async () => {
  if (!props.selectedCampaign?.id) return;

  isFetching.value = true;
  try {
    const response = await CampaignsAPI.metrics(props.selectedCampaign.id);
    metrics.value = response.data;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP_METRICS.API.ERROR_MESSAGE'));
  } finally {
    isFetching.value = false;
  }
};

const failedReasons = computed(() =>
  Object.entries(metrics.value?.failed_reasons || {})
);

watch(() => props.selectedCampaign, fetchMetrics);

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="alert"
    :title="t('CAMPAIGN.WHATSAPP_METRICS.TITLE')"
    :show-confirm-button="false"
    :cancel-button-label="t('CAMPAIGN.WHATSAPP_METRICS.CLOSE')"
    width="xl"
  >
    <div v-if="isFetching" class="flex items-center justify-center py-10">
      <Spinner />
    </div>
    <div v-else-if="metrics" class="flex flex-col gap-4">
      <div class="flex flex-wrap gap-4">
        <ReportMetricCard
          class="flex-1 min-w-[8rem]"
          :label="t('CAMPAIGN.WHATSAPP_METRICS.AUDIENCE_COUNT.LABEL')"
          :info-text="t('CAMPAIGN.WHATSAPP_METRICS.AUDIENCE_COUNT.TOOLTIP')"
          :value="formatCount(metrics.audience_count)"
        />
        <ReportMetricCard
          class="flex-1 min-w-[8rem]"
          :label="t('CAMPAIGN.WHATSAPP_METRICS.SENT.LABEL')"
          :info-text="t('CAMPAIGN.WHATSAPP_METRICS.SENT.TOOLTIP')"
          :value="formatCount(metrics.sent)"
        />
        <ReportMetricCard
          class="flex-1 min-w-[8rem]"
          :label="t('CAMPAIGN.WHATSAPP_METRICS.DELIVERED.LABEL')"
          :info-text="t('CAMPAIGN.WHATSAPP_METRICS.DELIVERED.TOOLTIP')"
          :value="formatCount(metrics.delivered)"
        />
        <ReportMetricCard
          class="flex-1 min-w-[8rem]"
          :label="t('CAMPAIGN.WHATSAPP_METRICS.READ.LABEL')"
          :info-text="t('CAMPAIGN.WHATSAPP_METRICS.READ.TOOLTIP')"
          :value="formatCount(metrics.read)"
        />
      </div>
      <div class="flex flex-wrap gap-4">
        <ReportMetricCard
          class="flex-1 min-w-[8rem]"
          :label="t('CAMPAIGN.WHATSAPP_METRICS.FAILED.LABEL')"
          :info-text="t('CAMPAIGN.WHATSAPP_METRICS.FAILED.TOOLTIP')"
          :value="formatCount(metrics.failed)"
        />
        <ReportMetricCard
          class="flex-1 min-w-[8rem]"
          :label="t('CAMPAIGN.WHATSAPP_METRICS.RESPONDED.LABEL')"
          :info-text="t('CAMPAIGN.WHATSAPP_METRICS.RESPONDED.TOOLTIP')"
          :value="formatCount(metrics.responded)"
        />
        <ReportMetricCard
          class="flex-1 min-w-[8rem]"
          :label="t('CAMPAIGN.WHATSAPP_METRICS.RESPONSE_RATE.LABEL')"
          :info-text="t('CAMPAIGN.WHATSAPP_METRICS.RESPONSE_RATE.TOOLTIP')"
          :value="formatPercent(metrics.response_rate)"
        />
      </div>
      <div v-if="failedReasons.length" class="flex flex-col gap-1 mt-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.WHATSAPP_METRICS.FAILED.LABEL') }}
        </span>
        <div
          v-for="[reason, count] in failedReasons"
          :key="reason"
          class="flex justify-between text-sm text-n-slate-11"
        >
          <span class="truncate">{{ reason }}</span>
          <span>{{ count }}</span>
        </div>
      </div>
    </div>
  </Dialog>
</template>
