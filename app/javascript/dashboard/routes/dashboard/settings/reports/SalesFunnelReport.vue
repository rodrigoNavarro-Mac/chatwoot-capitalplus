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

const requestPayload = computed(() => ({
  from: toUnixSeconds(filters.value.since),
  to: toUnixSeconds(filters.value.until, true),
  inboxIds: filters.value.inboxId ? [filters.value.inboxId] : undefined,
}));

const developmentKeys = computed(() =>
  [...new Set(rows.value.map(row => row.development_key))].sort()
);

const fetchReport = async () => {
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
              {{ t('SALES_FUNNEL_REPORTS.FILTERS.INBOX') }}
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
          class="text-sm text-n-slate-11 py-4 text-center border border-n-weak rounded-lg mb-8"
        >
          {{ t('SALES_FUNNEL_REPORTS.TABLE.EMPTY') }}
        </div>

        <div
          v-for="row in rows"
          :key="row.inbox_id"
          class="flex flex-col gap-4 mb-6 p-4 border border-n-weak rounded-lg"
        >
          <div class="flex items-baseline justify-between">
            <h3 class="text-sm font-medium text-n-slate-12 m-0">
              {{ row.inbox_name }}
            </h3>
            <span class="text-xs text-n-slate-11">
              {{ t('SALES_FUNNEL_REPORTS.TABLE.DEVELOPMENT') }}:
              {{ row.development_key }}
            </span>
          </div>

          <FunnelStageMeter
            v-for="stage in row.stages"
            :key="stage.stage"
            :label="t(`SALES_FUNNEL_REPORTS.STAGES.${stage.stage}`)"
            :count="stage.count"
            :actual-percent="stage.actual_percent"
            :target-percent="stage.target_percent"
            :delta="stage.delta"
          />
        </div>

        <SalesFunnelGoalsManager
          :development-keys="developmentKeys"
          @saved="fetchReport"
        />
      </template>
    </div>
  </div>
</template>
