<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ReportsAPI from 'dashboard/api/reports';
import ZohoCrmAPI from 'dashboard/api/integrations/zoho_crm';
import ReportHeader from './components/ReportHeader.vue';
import FunnelStageMeter from './components/FunnelStageMeter.vue';
import SalesFunnelGoalsManager from './components/SalesFunnelGoalsManager.vue';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const eventTypeLabel = stage =>
  t(`REVENUE_INTELLIGENCE_REPORTS.EVENT_TYPES.${stage.toUpperCase()}`);

// Un icono por etapa + un ancho relativo decreciente (ver FunnelStageMeter) para que las 5
// filas se lean como un embudo angostándose en vez de una lista plana de barras iguales -- mismas
// 5 etapas canónicas que usan Marketing/Overview de Revenue Intelligence (unificación 2026-10-09).
const STAGE_ICONS = {
  lead_created: 'i-lucide-users',
  lead_contacted: 'i-lucide-message-circle',
  deal_created: 'i-lucide-handshake',
  visit_effective: 'i-lucide-map-pin',
  closed_won: 'i-lucide-trophy',
};
const STAGE_TAPER = {
  lead_created: 100,
  lead_contacted: 92,
  deal_created: 84,
  visit_effective: 80,
  closed_won: 76,
};

const toDateInputValue = date => date.toISOString().slice(0, 10);

const filters = ref({
  since: toDateInputValue(new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)),
  until: toDateInputValue(new Date()),
  desarrollo: '',
});

const isLoading = ref(false);
// Siempre trae TODOS los desarrollos (nunca se manda el filtro al backend) -- el selector de
// desarrollo de abajo filtra en el cliente sobre esta lista completa, igual que antes el selector
// de inbox leía de una lista fija (useMapGetter) independiente del fetch. Así el propio selector
// nunca se queda sin opciones al filtrar (ver developmentKeys).
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
}));

const developmentKeys = computed(() =>
  [...new Set(rows.value.map(row => row.development_key))].sort()
);

const filteredRows = computed(() =>
  filters.value.desarrollo
    ? rows.value.filter(row => row.development_key === filters.value.desarrollo)
    : rows.value
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
watch([() => filters.value.since, () => filters.value.until], fetchReport);

const isSyncingDeals = ref(false);

// Encola Crm::Zoho::DealsSyncJob para esta cuenta (corre en background — el job normalmente
// corre solo/hora vía cron, este botón es para no tener que esperar la hora en punto). No
// refresca el reporte automáticamente: el job puede tardar y no hay forma de saber cuándo
// termina desde aquí.
const syncDeals = async () => {
  isSyncingDeals.value = true;
  try {
    await ZohoCrmAPI.syncDeals();
    useAlert(t('SALES_FUNNEL_REPORTS.SYNC.SUCCESS'));
  } catch (error) {
    useAlert(t('SALES_FUNNEL_REPORTS.SYNC.ERROR'));
  } finally {
    isSyncingDeals.value = false;
  }
};
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <ReportHeader
        :header-title="t('SALES_FUNNEL_REPORTS.HEADER')"
        :header-description="t('SALES_FUNNEL_REPORTS.DESCRIPTION')"
      >
        <Button
          size="sm"
          variant="outline"
          icon="i-lucide-refresh-cw"
          :is-loading="isSyncingDeals"
          :label="t('SALES_FUNNEL_REPORTS.SYNC.BUTTON')"
          @click="syncDeals"
        />
      </ReportHeader>

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
            {{ t('SALES_FUNNEL_REPORTS.FILTERS.DEVELOPMENT') }}
          </label>
          <select v-model="filters.desarrollo" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{ t('SALES_FUNNEL_REPORTS.FILTERS.ALL_DEVELOPMENTS') }}
            </option>
            <option v-for="key in developmentKeys" :key="key" :value="key">
              {{ key }}
            </option>
          </select>
        </div>
      </div>

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner />
      </div>

      <template v-else>
        <div
          v-if="!filteredRows.length"
          class="text-sm text-n-slate-11 py-8 text-center rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
        >
          {{ t('SALES_FUNNEL_REPORTS.TABLE.EMPTY') }}
        </div>

        <div
          v-for="row in filteredRows"
          :key="row.development_key"
          class="flex flex-col gap-5 mb-4 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 m-0">
            {{ row.development_key }}
          </h3>

          <FunnelStageMeter
            v-for="stage in row.stages"
            :key="stage.stage"
            :icon="STAGE_ICONS[stage.stage]"
            :label="eventTypeLabel(stage.stage)"
            :count="stage.count"
            :actual-percent="stage.actual_percent"
            :target-percent="stage.target_percent"
            :delta="stage.delta"
            :taper-percent="STAGE_TAPER[stage.stage]"
            :activity-count="stage.seguimiento_count"
            :activity-tooltip="
              t('REVENUE_INTELLIGENCE_REPORTS.FUNNEL.SEGUIMIENTO_TOOLTIP')
            "
            :lost-count="stage.lost_count"
            :lost-tooltip="
              t('REVENUE_INTELLIGENCE_REPORTS.FUNNEL.LOST_TOOLTIP')
            "
          />

          <div
            v-if="row.calls && row.calls.total"
            class="text-sm text-n-slate-11 flex items-center gap-2"
          >
            <fluent-icon icon="call" size="14" />
            {{
              t('SALES_FUNNEL_REPORTS.CALLS.SUMMARY', {
                total: row.calls.total,
                percent: row.calls.answered_percent,
              })
            }}
          </div>
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
