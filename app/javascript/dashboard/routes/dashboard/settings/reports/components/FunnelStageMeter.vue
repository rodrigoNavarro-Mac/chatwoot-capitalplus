<script setup>
defineProps({
  icon: {
    type: String,
    required: true,
  },
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
  // Ancho máximo relativo (0-100) de esta fila respecto al ancho de la card — decrece por
  // etapa para que las 4 filas se lean como un embudo angostándose, no como una lista plana.
  taperPercent: {
    type: Number,
    default: 100,
  },
  // Cifra de actividad (V2::Reports::ZohoLeadsMetrics#deals_activity) para esta etapa: deals
  // CREADOS en el periodo por su etapa actual, sin el filtro de cohorte de `count`/`actualPercent`
  // (que solo cuenta leads cuya primera conversación cayó en el periodo). Se pinta como badge
  // aparte, no como parte de la barra — mezclarlo en la misma barra de % sumaría dos preguntas
  // distintas (cohorte vs actividad) bajo un solo número — el mismo sesgo que ya se corrigió en la
  // distribución del pipeline (ver ZohoLeadsMetrics#summary).
  activityCount: {
    type: Number,
    default: null,
  },
  activityTooltip: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <div class="mx-auto w-full" :style="{ maxWidth: `${taperPercent}%` }">
    <div class="flex items-center justify-between gap-2 text-sm mb-1.5">
      <span class="flex items-center gap-1.5 text-n-slate-12 font-medium">
        <span :class="icon" class="size-3.5 text-n-slate-9 flex-shrink-0" />
        {{ label }}
      </span>
      <span class="flex items-baseline gap-1.5 flex-shrink-0 tabular-nums">
        <span class="text-n-slate-10 text-xs">{{ count }}</span>
        <span class="text-n-slate-12 font-semibold">{{ actualPercent }}%</span>
        <span
          v-if="targetPercent !== null"
          class="text-xs font-medium"
          :class="delta >= 0 ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          {{ delta >= 0 ? '+' : '' }}{{ delta }}%
        </span>
        <span
          v-if="activityCount"
          v-tooltip="activityTooltip"
          class="text-xs font-medium px-1.5 rounded-full bg-n-amber-3 text-n-amber-11"
        >
          +{{ activityCount }}
        </span>
      </span>
    </div>
    <div
      class="relative w-full h-1.5 rounded-full bg-n-slate-3 overflow-hidden"
    >
      <div
        class="h-full rounded-full bg-n-brand"
        :style="{
          width: `${actualPercent > 0 ? Math.max(actualPercent, 4) : 0}%`,
        }"
      />
      <div
        v-if="targetPercent !== null"
        v-tooltip="`Meta: ${targetPercent}%`"
        class="absolute top-1/2 -translate-y-1/2 h-2.5 w-px bg-n-slate-12"
        :style="{ left: `${Math.min(Math.max(targetPercent, 0), 100)}%` }"
      />
    </div>
  </div>
</template>
