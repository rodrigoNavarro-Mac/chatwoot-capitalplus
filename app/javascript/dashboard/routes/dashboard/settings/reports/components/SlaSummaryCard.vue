<script setup>
import { useI18n } from 'vue-i18n';

defineProps({
  titleKey: { type: String, required: true },
  pendingKey: {
    type: String,
    default: 'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SLA_PENDING',
  },
  sla: { type: Object, default: null },
});

const { t } = useI18n();

const formatSeconds = seconds => {
  if (seconds === null || seconds === undefined)
    return t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.NA');
  const minutes = Math.floor(seconds / 60);
  const remaining = Math.round(seconds % 60);
  return minutes > 0 ? `${minutes}m ${remaining}s` : `${remaining}s`;
};
const formatPercent = value =>
  value === null || value === undefined
    ? t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.NA')
    : `${(value * 100).toFixed(1)}%`;

// Mismo semáforo que el resto de Marketing (sección 9 del brief: "no colores arbitrarios").
const NEAR_MARGIN = 0.2;
const targetStatus = (value, { max } = {}) => {
  if (value === null || value === undefined) return 'unknown';
  if (value <= max) return 'on_target';
  if (value <= max * (1 + NEAR_MARGIN)) return 'near_target';
  return 'off_target';
};
const STATUS_CLASSES = {
  on_target: 'text-n-teal-11',
  near_target: 'text-n-amber-11',
  off_target: 'text-n-ruby-11',
  unknown: 'text-n-slate-11',
};
const statusClass = status => STATUS_CLASSES[status] || STATUS_CLASSES.unknown;
</script>

<template>
  <div
    class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
  >
    <h3 class="text-base font-semibold text-n-slate-12 mt-0 mb-1">
      {{ t(titleKey) }}
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
          {{ t(pendingKey) }}
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
</template>
