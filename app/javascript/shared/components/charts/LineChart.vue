<script setup>
import { computed, ref } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  Title,
  Tooltip,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale,
} from 'chart.js';

const props = defineProps({
  collection: {
    type: Object,
    default: () => ({}),
  },
  chartOptions: {
    type: Object,
    default: () => ({}),
  },
});

ChartJS.register(
  Title,
  Tooltip,
  LineElement,
  PointElement,
  CategoryScale,
  LinearScale
);

const fontFamily =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';

const defaultChartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  legend: {
    display: false,
    labels: {
      fontFamily,
    },
  },
  animation: {
    duration: 0,
  },
  elements: {
    line: {
      tension: 0.2,
    },
    point: {
      radius: 4,
      hoverRadius: 6,
    },
  },
  scales: {
    x: {
      ticks: {
        fontFamily: fontFamily,
      },
      grid: {
        drawOnChartArea: false,
      },
    },
    y: {
      type: 'linear',
      position: 'left',
      ticks: {
        fontFamily: fontFamily,
        beginAtZero: true,
        stepSize: 1,
      },
      grid: {
        drawOnChartArea: false,
      },
    },
  },
};

const options = computed(() => {
  return { ...defaultChartOptions, ...props.chartOptions };
});

// Reexpone la instancia de Chart.js del <Line> interno (vue-chartjs) para que un padre pueda
// exportarla a imagen (chart.toBase64Image()), mismo patrón que BarChart.vue.
const lineRef = ref(null);
defineExpose({
  chart: computed(() => lineRef.value?.chart),
});
</script>

<template>
  <Line ref="lineRef" :data="collection" :options="options" />
</template>
