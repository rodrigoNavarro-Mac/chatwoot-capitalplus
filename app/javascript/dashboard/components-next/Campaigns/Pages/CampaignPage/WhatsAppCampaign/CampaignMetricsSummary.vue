<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ReportMetricCard from 'dashboard/routes/dashboard/settings/reports/components/ReportMetricCard.vue';

const props = defineProps({
  metrics: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const formatCount = value => (value ?? 0).toLocaleString();
const formatPercent = value => `${value ?? 0}%`;

const failedReasons = computed(() =>
  Object.entries(props.metrics?.failed_reasons || {})
);
</script>

<template>
  <div class="flex flex-col gap-4">
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
</template>
