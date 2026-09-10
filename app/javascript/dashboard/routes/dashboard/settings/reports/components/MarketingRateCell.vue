<script setup>
defineProps({
  rate: { type: Number, default: null },
});
</script>

<template>
  <div class="flex flex-col gap-1 min-w-[4.5rem]">
    <span class="text-n-slate-12 tabular-nums text-sm">
      {{ rate === null ? '—' : `${rate}%` }}
    </span>
    <div
      v-if="rate !== null"
      class="w-full h-1 rounded-full bg-n-slate-3 overflow-hidden"
    >
      <div
        class="h-full bg-n-brand rounded-full"
        :style="{ width: `${Math.min(Math.max(rate, 0), 100)}%` }"
      />
    </div>
  </div>
</template>
