<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import ReportsAPI from 'dashboard/api/reports';
import ReportHeader from './components/ReportHeader.vue';
import FunnelStageMeter from './components/FunnelStageMeter.vue';
import SalesFunnelGoalsManager from './components/SalesFunnelGoalsManager.vue';
import Spinner from 'shared/components/Spinner.vue';

const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

// Un icono por etapa + un ancho relativo decreciente (ver FunnelStageMeter) para que las 4
// filas se lean como un embudo angostándose en vez de una lista plana de barras iguales.
const STAGE_ICONS = {
  leads: 'i-lucide-users',
  customer_replied: 'i-lucide-message-circle',
  has_deal: 'i-lucide-handshake',
  closed_won: 'i-lucide-trophy',
};
const STAGE_TAPER = {
  leads: 100,
  customer_replied: 92,
  has_deal: 84,
  closed_won: 76,
};

const toDateInputValue = date => date.toISOString().slice(0, 10);

const filters = ref({
  since: toDateInputValue(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)),
  until: toDateInputValue(new Date()),
  inboxId: '',
});

const isLoading = ref(false);
const rows = ref([]);

const toUnixSeconds = (dateValue, endOfDay = false) => {
  const date = new Date(`${dateValue}T${endOfDay ? '23:59:59' : '00:00:00'}`);
  return Math.floor(date.getTime() / 1000).toString();
};

// Los inputs type="date" emiten un update por cada tecla mientras se escribe la fecha a mano
// (ej. el año a medio escribir) — sin este guard, esos estados intermedios disparaban un fetch
// con una fecha inválida y mostraban un error falso.
const isCompleteDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value);
const hasValidDateRange = computed(
  () =>
    isCompleteDate(filters.value.since) && isCompleteDate(filters.value.until)
);

const requestPayload = computed(() => ({
  from: toUnixSeconds(filters.value.since),
  to: toUnixSeconds(filters.value.until, true),
  inboxIds: filters.value.inboxId ? [filters.value.inboxId] : undefined,
}));

const developmentKeys = computed(() =>
  [...new Set(rows.value.map(row => row.development_key))].sort()
);

const fetchReport = async () => {
  if (!hasValidDateRange.value) return;

  isLoading.value = true;
  try {
    const response = await ReportsAPI.getSalesFunnelReport(
      requestPayload.value
    );
    rows.value = response.data;
  } catch (error) {
    useAlert(t('SALES_FUNNEL_REPORTS.ERRORS.FETCH'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(fetchReport);
watch(filters, fetchReport, { deep: true });
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <ReportHeader
        :header-title="t('SALES_FUNNEL_REPORTS.HEADER')"
        :header-description="t('SALES_FUNNEL_REPORTS.DESCRIPTION')"
      />

      <div class="flex flex-wrap items-end gap-3 mb-6">
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('SALES_FUNNEL_REPORTS.FILTERS.SINCE') }}
          </label>
          <input
            v-model="filters.since"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('SALES_FUNNEL_REPORTS.FILTERS.UNTIL') }}
          </label>
          <input
            v-model="filters.until"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('SALES_FUNNEL_REPORTS.FILTERS.INBOX') }}
          </label>
          <select v-model="filters.inboxId" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{ t('SALES_FUNNEL_REPORTS.FILTERS.ALL_INBOXES') }}
            </option>
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner />
      </div>

      <template v-else>
        <div
          v-if="!rows.length"
          class="text-sm text-n-slate-11 py-8 text-center rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
        >
          {{ t('SALES_FUNNEL_REPORTS.TABLE.EMPTY') }}
        </div>

        <div
          v-for="row in rows"
          :key="row.inbox_id"
          class="flex flex-col gap-5 mb-4 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-base font-semibold text-n-slate-12 m-0">
              {{ row.inbox_name }}
            </h3>
            <span
              class="text-xs px-2 py-0.5 rounded-full bg-n-slate-3 text-n-slate-11 flex-shrink-0"
            >
              {{ t('SALES_FUNNEL_REPORTS.TABLE.DEVELOPMENT') }}:
              {{ row.development_key }}
            </span>
          </div>

          <FunnelStageMeter
            v-for="stage in row.stages"
            :key="stage.stage"
            :icon="STAGE_ICONS[stage.stage]"
            :label="t(`SALES_FUNNEL_REPORTS.STAGES.${stage.stage}`)"
            :count="stage.count"
            :actual-percent="stage.actual_percent"
            :target-percent="stage.target_percent"
            :delta="stage.delta"
            :taper-percent="STAGE_TAPER[stage.stage]"
          />
        </div>

        <div
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mt-2"
        >
          <SalesFunnelGoalsManager
            :development-keys="developmentKeys"
            @saved="fetchReport"
          />
        </div>
      </template>
    </div>
  </div>
</template>
