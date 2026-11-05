<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Side-by-side funnel of the two templates of an A/B test campaign (metrics.variants from
// Campaigns::CampaignMetricsBuilder).
const props = defineProps({
  variants: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

// Below this many sends per template a difference in response rate is mostly noise
const MIN_SENT_PER_VARIANT = 100;

const rate = (part, total) =>
  total ? `${((part / total) * 100).toFixed(1)}%` : '—';

const columns = computed(() =>
  ['A', 'B'].map(key => {
    const v = props.variants[key] || {};
    return {
      key,
      templateName: v.template_name || '—',
      sent: v.sent ?? 0,
      deliveredRate: rate(v.delivered, v.sent),
      readRate: rate(v.read, v.sent),
      failed: v.failed ?? 0,
      responded: v.responded ?? 0,
      responseRate: v.response_rate ?? 0,
    };
  })
);

const rows = computed(() => [
  {
    label: t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.ROWS.SENT'),
    field: 'sent',
  },
  {
    label: t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.ROWS.DELIVERED'),
    field: 'deliveredRate',
  },
  {
    label: t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.ROWS.READ'),
    field: 'readRate',
  },
  {
    label: t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.ROWS.RESPONDED'),
    field: 'responded',
  },
  {
    label: t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.ROWS.RESPONSE_RATE'),
    field: 'responseRate',
    suffix: '%',
  },
  {
    label: t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.ROWS.FAILED'),
    field: 'failed',
  },
]);

const hasEnoughData = computed(() =>
  columns.value.every(column => column.sent >= MIN_SENT_PER_VARIANT)
);

const leader = computed(() => {
  if (!hasEnoughData.value) return null;
  const [a, b] = columns.value;
  if (a.responseRate === b.responseRate) return null;
  return a.responseRate > b.responseRate ? a : b;
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.TITLE') }}
    </span>
    <div class="overflow-x-auto border rounded-xl border-n-weak">
      <table class="w-full text-sm">
        <thead>
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-normal text-left text-n-slate-11" />
            <th
              v-for="column in columns"
              :key="column.key"
              class="px-3 py-2 text-left"
            >
              <span class="font-semibold text-n-slate-12">
                {{
                  t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.TEMPLATE', {
                    key: column.key,
                  })
                }}
              </span>
              <span class="block text-xs font-normal text-n-slate-11">
                {{ column.templateName }}
              </span>
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="row in rows"
            :key="row.field"
            class="border-b last:border-b-0 border-n-weak"
          >
            <td class="px-3 py-2 text-n-slate-11">{{ row.label }}</td>
            <td
              v-for="column in columns"
              :key="column.key"
              class="px-3 py-2 tabular-nums text-n-slate-12"
              :class="{
                'font-semibold text-n-teal-11':
                  row.field === 'responseRate' && leader?.key === column.key,
              }"
            >
              {{ column[row.field] }}{{ row.suffix || '' }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <p class="text-xs text-n-slate-11">
      <template v-if="leader">
        {{
          t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.LEADER', {
            key: leader.key,
            rate: leader.responseRate,
          })
        }}
      </template>
      <template v-else-if="!hasEnoughData">
        {{
          t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.NOT_ENOUGH_DATA', {
            count: MIN_SENT_PER_VARIANT,
          })
        }}
      </template>
      <template v-else>
        {{ t('CAMPAIGN.WHATSAPP_METRICS.AB_TEST.TIE') }}
      </template>
    </p>
  </div>
</template>
