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

const COLOR_MAP = {
  active: 'bg-n-teal-3 text-n-teal-11',
  waiting_response: 'bg-n-amber-3 text-n-amber-11',
  pending_agent_call: 'bg-n-ruby-3 text-n-ruby-11',
  paused_by_response: 'bg-n-blue-3 text-n-blue-11',
  completed: 'bg-n-slate-4 text-n-slate-11',
  failed: 'bg-n-ruby-3 text-n-ruby-11',
  recovered: 'bg-n-teal-3 text-n-teal-11',
  cold: 'bg-n-slate-4 text-n-slate-11',
};

const colorClass = computed(
  () => COLOR_MAP[props.status] || 'bg-n-slate-4 text-n-slate-11'
);
const label = computed(() => t(`CADENCE.STATUS.${props.status}`));
</script>

<template>
  <span
    class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap"
    :class="colorClass"
  >
    {{ label }}
  </span>
</template>
