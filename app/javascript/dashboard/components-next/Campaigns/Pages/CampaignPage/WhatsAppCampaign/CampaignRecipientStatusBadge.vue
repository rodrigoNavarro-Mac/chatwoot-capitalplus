<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  status: {
    type: String,
    required: true,
  },
});

const { t } = useI18n();

const STATUS_CLASSES = {
  queued: 'bg-n-slate-3 text-n-slate-11',
  sent: 'bg-n-amber-3 text-n-amber-11',
  delivered: 'bg-n-blue-3 text-n-blue-11',
  read: 'bg-n-teal-3 text-n-teal-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
};

const STATUS_LABEL_KEYS = {
  queued: 'CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.QUEUED',
  sent: 'CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.SENT',
  delivered: 'CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.DELIVERED',
  read: 'CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.READ',
  failed: 'CAMPAIGN.WHATSAPP_RECIPIENTS.FILTERS.STATUS.FAILED',
};

const badgeClass = computed(
  () => STATUS_CLASSES[props.status] || 'bg-n-slate-3 text-n-slate-11'
);
const label = computed(() =>
  t(STATUS_LABEL_KEYS[props.status] || props.status)
);
</script>

<template>
  <span
    class="inline-flex items-center h-6 px-2 py-0.5 rounded-md text-xs font-medium whitespace-nowrap"
    :class="badgeClass"
  >
    {{ label }}
  </span>
</template>
