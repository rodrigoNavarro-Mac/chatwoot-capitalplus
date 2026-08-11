<script setup>
import { ref, computed, nextTick, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import WeeklyOpsReportsAPI from 'dashboard/api/weeklyOpsReports';
import { downloadBlobFile } from 'dashboard/helper/downloadHelper';
import ReportHeader from './components/ReportHeader.vue';
import FunnelStageMeter from './components/FunnelStageMeter.vue';
import ReportMetricCard from './components/ReportMetricCard.vue';
import ReportBrandingPanel from './components/ReportBrandingPanel.vue';
import BarChart from 'shared/components/charts/BarChart.vue';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const inboxes = useMapGetter('inboxes/getInboxes');

const STAGE_ICONS = {
  leads: 'i-lucide-users',
  customer_replied: 'i-lucide-message-circle',
  has_deal: 'i-lucide-handshake',
  visita_efectiva: 'i-lucide-map-pin',
  closed_won: 'i-lucide-trophy',
};
const STAGE_TAPER = {
  leads: 100,
  customer_replied: 92,
  has_deal: 84,
  visita_efectiva: 80,
  closed_won: 76,
};

const toDateInputValue = date => date.toISOString().slice(0, 10);

// Por defecto, la última semana lunes-domingo ya cerrada.
const defaultRange = () => {
  const now = new Date();
  const day = now.getDay();
  const diffToLastMonday = day === 0 ? 13 : day + 6;
  const since = new Date(now);
  since.setDate(now.getDate() - diffToLastMonday);
  const until = new Date(since);
  until.setDate(since.getDate() + 6);
  return { since: toDateInputValue(since), until: toDateInputValue(until) };
};

const filters = ref({ inboxId: '', ...defaultRange() });

const isLoading = ref(false);
const report = ref(null);
const isDownloading = ref(false);

const contactTimeChartRef = ref(null);
const cadenceChartRef = ref(null);

const isCompleteDate = value => /^\d{4}-\d{2}-\d{2}$/.test(value);
const canGenerate = computed(
  () =>
    !!filters.value.inboxId &&
    isCompleteDate(filters.value.since) &&
    isCompleteDate(filters.value.until)
);

const toUnixSeconds = (dateValue, endOfDay = false) => {
  const date = new Date(`${dateValue}T${endOfDay ? '23:59:59' : '00:00:00'}`);
  return Math.floor(date.getTime() / 1000).toString();
};

const kpis = computed(() => report.value?.kpis || null);

const contactTimeChartData = computed(() => {
  const current = kpis.value?.contact_time || {};
  const previous = kpis.value?.comparison?.contact_time || {};
  return {
    labels: [
      t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE'),
      t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME'),
    ],
    datasets: [
      {
        label: t('WEEKLY_OPS_REPORTS.CHART.CURRENT_PERIOD'),
        backgroundColor: '#1f77b4',
        data: [current.first_response || 0, current.reply_time || 0],
      },
      {
        label: t('WEEKLY_OPS_REPORTS.CHART.PREVIOUS_PERIOD'),
        backgroundColor: '#c7c7c7',
        data: [previous.first_response || 0, previous.reply_time || 0],
      },
    ],
  };
});

const discardReasonsTotal = computed(() => {
  const reasons = kpis.value?.zoho_leads?.discard_reasons || {};
  return Object.values(reasons).reduce((sum, count) => sum + count, 0);
});

const percentOf = (count, total) =>
  total > 0 ? `${((count / total) * 100).toFixed(1)}%` : '0%';

const cadenceChartData = computed(() => {
  const byStatus = kpis.value?.cadences?.by_status || {};
  const labels = Object.keys(byStatus);
  return {
    labels,
    datasets: [
      {
        label: t('WEEKLY_OPS_REPORTS.CADENCES.BY_STATUS'),
        backgroundColor: '#ff7f0e',
        data: labels.map(label => byStatus[label]),
      },
    ],
  };
});

// Si ya existe un reporte generado para el inbox y el rango de fechas seleccionados, lo precarga
// en vez de dejar la pantalla vacía esperando a que el usuario le dé "Generar reporte" de nuevo.
const loadExistingReport = async () => {
  report.value = null;
  if (!canGenerate.value) return;

  isLoading.value = true;
  try {
    const { data } = await WeeklyOpsReportsAPI.getReports(
      filters.value.inboxId
    );
    const match = data.find(
      existing =>
        existing.period_start === filters.value.since &&
        existing.period_end === filters.value.until &&
        existing.status === 'completed'
    );
    if (match) {
      const response = await WeeklyOpsReportsAPI.getReport(
        filters.value.inboxId,
        match.id
      );
      report.value = response.data;
    }
  } catch (error) {
    // Silencioso: si falla la precarga, el usuario igual puede generar manualmente.
  } finally {
    isLoading.value = false;
  }
};

watch(
  () => [filters.value.inboxId, filters.value.since, filters.value.until],
  loadExistingReport
);

const fetchOrGenerate = async () => {
  if (!canGenerate.value) return;

  isLoading.value = true;
  try {
    const response = await WeeklyOpsReportsAPI.generateReport(
      filters.value.inboxId,
      {
        since: toUnixSeconds(filters.value.since),
        until: toUnixSeconds(filters.value.until, true),
      }
    );
    report.value = response.data;
  } catch (error) {
    useAlert(t('WEEKLY_OPS_REPORTS.ERRORS.GENERATE'));
  } finally {
    isLoading.value = false;
  }
};

const downloadPdf = async () => {
  if (!report.value) return;

  isDownloading.value = true;
  try {
    await nextTick();
    const chartImages = [
      contactTimeChartRef.value?.chart && {
        title: t('WEEKLY_OPS_REPORTS.CONTACT_TIME.TITLE'),
        data_url: contactTimeChartRef.value.chart.toBase64Image(),
      },
      cadenceChartRef.value?.chart && {
        title: t('WEEKLY_OPS_REPORTS.CADENCES.BY_STATUS'),
        data_url: cadenceChartRef.value.chart.toBase64Image(),
      },
    ].filter(Boolean);

    const response = await WeeklyOpsReportsAPI.downloadPdf(
      filters.value.inboxId,
      report.value.id,
      chartImages
    );
    downloadBlobFile(
      `reporte-semanal-${report.value.inbox_id}-${report.value.period_start}.pdf`,
      response.data
    );
  } catch (error) {
    useAlert(t('WEEKLY_OPS_REPORTS.ERRORS.DOWNLOAD'));
  } finally {
    isDownloading.value = false;
  }
};
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <ReportHeader
        :header-title="t('WEEKLY_OPS_REPORTS.HEADER')"
        :header-description="t('WEEKLY_OPS_REPORTS.DESCRIPTION')"
      >
        <Button
          size="sm"
          variant="outline"
          icon="i-lucide-download"
          :is-loading="isDownloading"
          :disabled="!report"
          :label="t('WEEKLY_OPS_REPORTS.DOWNLOAD_PDF')"
          @click="downloadPdf"
        />
      </ReportHeader>

      <div class="flex flex-wrap items-end gap-3 mb-6">
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('WEEKLY_OPS_REPORTS.FILTERS.INBOX') }}
          </label>
          <select v-model="filters.inboxId" class="!mb-0 !h-8 text-sm">
            <option value="">
              {{ t('WEEKLY_OPS_REPORTS.FILTERS.SELECT_INBOX') }}
            </option>
            <option v-for="inbox in inboxes" :key="inbox.id" :value="inbox.id">
              {{ inbox.name }}
            </option>
          </select>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('WEEKLY_OPS_REPORTS.FILTERS.SINCE') }}
          </label>
          <input
            v-model="filters.since"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-xs text-n-slate-11">
            {{ t('WEEKLY_OPS_REPORTS.FILTERS.UNTIL') }}
          </label>
          <input
            v-model="filters.until"
            type="date"
            class="!mb-0 !h-8 text-sm"
          />
        </div>
        <Button
          size="sm"
          icon="i-lucide-sparkles"
          :is-loading="isLoading"
          :disabled="!canGenerate"
          :label="t('WEEKLY_OPS_REPORTS.GENERATE')"
          @click="fetchOrGenerate"
        />
      </div>

      <ReportBrandingPanel v-if="filters.inboxId" :inbox-id="filters.inboxId" />

      <div v-if="isLoading" class="flex justify-center py-8">
        <Spinner />
      </div>

      <div
        v-else-if="!report"
        class="text-sm text-n-slate-11 py-8 text-center rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 mb-6"
      >
        {{ t('WEEKLY_OPS_REPORTS.EMPTY') }}
      </div>

      <template v-else>
        <div
          class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <ReportMetricCard
            :label="t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE')"
            :value="`${kpis.contact_time.first_response ?? '—'} min`"
            :info-text="
              t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE_INFO')
            "
          />
          <ReportMetricCard
            :label="t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME')"
            :value="`${kpis.contact_time.reply_time ?? '—'} min`"
            :info-text="t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME_INFO')"
          />
          <ReportMetricCard
            :label="t('WEEKLY_OPS_REPORTS.VOLUME.NEW_CONVERSATIONS')"
            :value="String(kpis.volume.new_conversations)"
            :info-text="t('WEEKLY_OPS_REPORTS.VOLUME.NEW_CONVERSATIONS_INFO')"
          />
          <ReportMetricCard
            :label="t('WEEKLY_OPS_REPORTS.CADENCES.RESPONSE_RATE')"
            :value="`${kpis.cadences.response_rate ?? 0}%`"
            :info-text="t('WEEKLY_OPS_REPORTS.CADENCES.RESPONSE_RATE_INFO')"
          />
        </div>

        <div
          v-if="kpis.by_advisor && kpis.by_advisor.length"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.BY_ADVISOR.TITLE') }}
          </h3>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.BY_ADVISOR.ADVISOR') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.BY_ADVISOR.CONVERSATIONS') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.CONTACT_TIME.FIRST_RESPONSE') }}
                </th>
                <th class="py-1 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.CONTACT_TIME.REPLY_TIME') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="advisor in kpis.by_advisor"
                :key="advisor.user_id"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ advisor.name }}</td>
                <td class="py-1.5 pr-3">{{ advisor.conversations_count }}</td>
                <td class="py-1.5 pr-3">
                  {{ `${advisor.contact_time.first_response ?? '—'} min` }}
                </td>
                <td class="py-1.5">
                  {{ `${advisor.contact_time.reply_time ?? '—'} min` }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.CONTACT_TIME.TITLE') }}
          </h3>
          <div class="h-64">
            <BarChart
              ref="contactTimeChartRef"
              :collection="contactTimeChartData"
            />
          </div>
        </div>

        <div
          v-if="
            kpis.cadences.by_status &&
            Object.keys(kpis.cadences.by_status).length
          "
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.CADENCES.BY_STATUS') }}
          </h3>
          <div class="h-64">
            <BarChart ref="cadenceChartRef" :collection="cadenceChartData" />
          </div>
        </div>

        <div
          v-if="kpis.pipeline"
          class="flex flex-col gap-5 mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 m-0">
            {{ t('WEEKLY_OPS_REPORTS.PIPELINE.TITLE') }}
          </h3>
          <FunnelStageMeter
            v-for="stage in kpis.pipeline.stages"
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
          v-if="kpis.zoho_leads"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.PIPELINE_STATUS_TITLE') }}
          </h3>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.STATUS') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS') }}
                </th>
                <th class="py-1 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(count, status) in kpis.zoho_leads.by_status"
                :key="status"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ status }}</td>
                <td class="py-1.5 pr-3">{{ count }}</td>
                <td class="py-1.5">
                  {{ percentOf(count, kpis.zoho_leads.total) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="kpis.zoho_leads"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.SOURCE_TITLE') }}
          </h3>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.SOURCE') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS') }}
                </th>
                <th class="py-1 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(count, source) in kpis.zoho_leads.by_source"
                :key="source"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ source }}</td>
                <td class="py-1.5 pr-3">{{ count }}</td>
                <td class="py-1.5">
                  {{ percentOf(count, kpis.zoho_leads.total) }}
                </td>
              </tr>
            </tbody>
          </table>
          <p class="text-sm text-n-slate-11 mt-3 mb-0">
            {{
              t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.QUALITY_LEADS', {
                count: kpis.zoho_leads.quality_leads_count,
                percent: kpis.zoho_leads.quality_leads_percent,
              })
            }}
          </p>
        </div>

        <div
          v-if="discardReasonsTotal"
          class="mb-6 p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2 overflow-x-auto"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.DISCARD_TITLE') }}
          </h3>
          <table class="w-full text-sm">
            <thead>
              <tr class="text-left text-n-slate-11">
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.REASON') }}
                </th>
                <th class="py-1 pr-3 font-medium">
                  {{ t('WEEKLY_OPS_REPORTS.ZOHO_LEADS.LEADS') }}
                </th>
                <th class="py-1 font-medium">%</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="(count, reason) in kpis.zoho_leads.discard_reasons"
                :key="reason"
                class="border-t border-n-container text-n-slate-12"
              >
                <td class="py-1.5 pr-3">{{ reason }}</td>
                <td class="py-1.5 pr-3">{{ count }}</td>
                <td class="py-1.5">
                  {{ percentOf(count, discardReasonsTotal) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div
          v-if="report.llm_analysis"
          class="p-5 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
        >
          <h3 class="text-base font-semibold text-n-slate-12 mb-3">
            {{ t('WEEKLY_OPS_REPORTS.ANALYSIS.TITLE') }}
          </h3>
          <p class="text-sm text-n-slate-11 whitespace-pre-line m-0">
            {{ report.llm_analysis }}
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
