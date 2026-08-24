<script setup>
import { computed } from 'vue';

const props = defineProps({
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
  // Cuánto de `count`/`actualPercent` viene de actividad fuera de la cohorte de "leads nuevos del
  // periodo" -- deals CREADOS este periodo de leads que llegaron antes (ver
  // V2::Reports::SalesFunnelBuilder#deal_activity_outside_cohort). Ya está SUMADO dentro de
  // `count`/`actualPercent` (así cuenta para el % y la meta) — este prop solo dice cuánto de ese
  // total pintar en otro color, no es un número aparte que haya que sumar.
  activityCount: {
    type: Number,
    default: null,
  },
  activityTooltip: {
    type: String,
    default: '',
  },
});

// El track se pinta 0-100 aunque actualPercent pase de 100 (posible cuando la actividad fuera de
// cohorte es grande) — el número real igual se muestra sin recortar, solo la barra se topa.
const totalBarPercent = computed(() => Math.min(props.actualPercent, 100));
// Mismo mínimo visible que antes (4%) para que una etapa con muy poco % no desaparezca del todo,
// aplicado al total antes de partirlo en cohorte/actividad.
const visibleTotalWidth = computed(() =>
  totalBarPercent.value > 0 ? Math.max(totalBarPercent.value, 4) : 0
);
// División proporcional dentro del ancho visible: el backend solo manda el conteo de actividad, no
// su % por separado, así que se reparte el ancho según qué fracción de `count` es actividad.
const activityBarWidth = computed(() => {
  if (!props.activityCount || !props.count) return 0;
  return (props.activityCount / props.count) * visibleTotalWidth.value;
});
const cohortBarWidth = computed(() =>
  Math.max(visibleTotalWidth.value - activityBarWidth.value, 0)
);
</script>

<template>
  <div class="mx-auto w-full" :style="{ maxWidth: `${taperPercent}%` }">
    <div class="flex items-center justify-between gap-2 text-sm mb-1.5">
      <span class="flex items-center gap-1.5 text-n-slate-12 font-medium">
        <span :class="icon" class="size-3.5 text-n-slate-9 flex-shrink-0" />
        {{ label }}
      </span>
      <span class="flex items-baseline gap-1 flex-shrink-0 tabular-nums">
        <span class="text-n-slate-10 text-xs">
          {{ count }}
          <span
            v-if="activityCount"
            v-tooltip="activityTooltip"
            class="text-n-amber-11 font-medium"
          >
            (+{{ activityCount }})
          </span>
        </span>
        <span class="text-n-slate-12 font-semibold">{{ actualPercent }}%</span>
        <span
          v-if="targetPercent !== null"
          class="text-xs font-medium"
          :class="delta >= 0 ? 'text-n-teal-11' : 'text-n-ruby-11'"
        >
          {{ delta >= 0 ? '+' : '' }}{{ delta }}%
        </span>
      </span>
    </div>
    <div
      class="relative w-full h-1.5 rounded-full bg-n-slate-3 overflow-hidden flex"
    >
      <div
        class="h-full bg-n-brand flex-shrink-0"
        :style="{ width: `${cohortBarWidth}%` }"
      />
      <div
        v-if="activityBarWidth > 0"
        v-tooltip="activityTooltip"
        class="h-full bg-n-amber-10 flex-shrink-0"
        :style="{ width: `${activityBarWidth}%` }"
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
