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
  // Cuánto de `count`/`actualPercent` es "seguimiento" -- actividad de esta etapa sobre leads/deals
  // que ya existían ANTES del periodo elegido, no leads nuevos del periodo (ver
  // RevenueIntelligenceBuilder#funnel_seguimiento_counts). Ya está SUMADO dentro de
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
  // Cuánto de `count`/`actualPercent` ya está PERDIDO -- de los que llegaron a esta etapa, cuántos
  // terminaron descartados/perdidos sin avanzar a la siguiente (ver
  // RevenueIntelligenceBuilder#funnel_lost_counts). Igual que activityCount, ya está SUMADO dentro
  // de `count` -- este prop solo dice cuánto pintar en rojo, no es una cantidad aparte que haya que
  // sumar.
  lostCount: {
    type: Number,
    default: null,
  },
  lostTooltip: {
    type: String,
    default: '',
  },
});

// El track se pinta 0-100 aunque actualPercent pase de 100 (posible cuando la actividad de
// seguimiento es grande) — el número real igual se muestra sin recortar, solo la barra se topa.
const totalBarPercent = computed(() => Math.min(props.actualPercent, 100));
// Mismo mínimo visible que antes (4%) para que una etapa con muy poco % no desaparezca del todo,
// aplicado al total antes de partirlo en cohorte/seguimiento/perdidos.
const visibleTotalWidth = computed(() =>
  totalBarPercent.value > 0 ? Math.max(totalBarPercent.value, 4) : 0
);
// División proporcional dentro del ancho visible: el backend solo manda los conteos, no su % por
// separado, así que se reparte el ancho según qué fracción de `count` es cada grupo.
const widthFor = countValue => {
  if (!countValue || !props.count) return 0;
  return (countValue / props.count) * visibleTotalWidth.value;
};
const activityBarWidth = computed(() => widthFor(props.activityCount));
const lostBarWidth = computed(() => widthFor(props.lostCount));
const cohortBarWidth = computed(() =>
  Math.max(
    visibleTotalWidth.value - activityBarWidth.value - lostBarWidth.value,
    0
  )
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
          <span
            v-if="lostCount"
            v-tooltip="lostTooltip"
            class="text-n-ruby-11 font-medium"
          >
            ({{ lostCount }})
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
        v-if="lostBarWidth > 0"
        v-tooltip="lostTooltip"
        class="h-full bg-n-ruby-9 flex-shrink-0"
        :style="{ width: `${lostBarWidth}%` }"
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
