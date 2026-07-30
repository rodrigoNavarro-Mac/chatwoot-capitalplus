<script setup>
defineProps({
  label: {
    type: String,
    required: true,
  },
  count: {
    type: Number,
    required: true,
  },
  actualPercent: {
    type: Number,
    required: true,
  },
  targetPercent: {
    type: Number,
    default: null,
  },
  delta: {
    type: Number,
    default: null,
  },
});
</script>

<template>
  <div class="flex flex-col gap-1">
    <div class="flex items-center justify-between gap-2 text-sm">
      <span class="text-n-slate-12 font-medium">{{ label }}</span>
      <span class="flex items-center gap-2 flex-shrink-0">
        <span class="text-n-slate-11 tabular-nums">
          {{ count }} &middot; {{ actualPercent }}%
        </span>
        <span
          v-if="targetPercent !== null"
          class="tabular-nums"
          :class="delta >= 0 ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          {{ delta >= 0 ? '+' : '' }}{{ delta }}%
        </span>
      </span>
    </div>
    <div class="relative w-full h-2 rounded-full bg-n-slate-4 overflow-hidden">
      <div
        class="h-full rounded-full bg-n-brand"
        :style="{ width: `${Math.min(actualPercent, 100)}%` }"
      />
      <div
        v-if="targetPercent !== null"
        v-tooltip="`${targetPercent}%`"
        class="absolute top-0 h-full w-0.5 bg-n-slate-12"
        :style="{ left: `${Math.min(targetPercent, 100)}%` }"
      />
    </div>
  </div>
</template>
