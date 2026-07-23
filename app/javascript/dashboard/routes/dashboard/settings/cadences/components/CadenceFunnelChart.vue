<script setup>
import { computed } from 'vue';

const props = defineProps({
  steps: {
    type: Array,
    default: () => [],
  },
});

const maxSent = computed(() =>
  Math.max(...props.steps.map(step => step.sent), 1)
);

const barWidth = sent => `${Math.max((sent / maxSent.value) * 100, 4)}%`;
</script>

<template>
  <div v-if="steps.length" class="mb-6">
    <h3 class="text-sm font-medium text-n-slate-12 mb-1">
      {{ $t('CADENCE.FUNNEL.TITLE') }}
    </h3>
    <p class="text-xs text-n-slate-11 mb-3">
      {{ $t('CADENCE.FUNNEL.DESCRIPTION') }}
    </p>
    <div class="flex flex-col gap-2">
      <div
        v-for="step in steps"
        :key="step.step"
        class="flex items-center gap-3"
      >
        <span class="w-16 shrink-0 text-xs text-n-slate-11">
          {{ $t('CADENCE.STEPS_TABLE.STEP') }} {{ step.step }}
        </span>
        <div class="flex-1 bg-n-slate-3 rounded h-6 relative overflow-hidden">
          <div
            class="bg-n-blue-9 h-full rounded flex items-center px-2"
            :style="{ width: barWidth(step.sent) }"
          >
            <span class="text-xs text-white whitespace-nowrap">
              {{ $t('CADENCE.FUNNEL.SENT', { count: step.sent }) }}
            </span>
          </div>
        </div>
        <span
          v-if="step.drop_off_rate > 0"
          class="w-40 shrink-0 text-xs text-n-ruby-9"
        >
          {{ $t('CADENCE.FUNNEL.DROP_OFF', { rate: step.drop_off_rate }) }}
        </span>
        <span v-else class="w-40 shrink-0" />
      </div>
    </div>
  </div>
</template>
