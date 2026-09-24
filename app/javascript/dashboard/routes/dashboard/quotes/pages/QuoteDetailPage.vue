<script setup>
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { downloadBlobFile } from 'dashboard/helper/downloadHelper';
import QuotesAPI from 'dashboard/api/quotes';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const route = useRoute();

const quote = ref(null);
const isFetching = ref(false);
const isDownloading = ref(false);

const currency = value =>
  Number(value || 0).toLocaleString('es-MX', {
    style: 'currency',
    currency: 'MXN',
  });

const percent = value => `${Number(value || 0)}%`;

const fetchQuote = async () => {
  isFetching.value = true;
  try {
    const response = await QuotesAPI.show(route.params.quoteId);
    quote.value = response.data;
  } catch (error) {
    useAlert(t('QUOTES.ERRORS.FETCH'));
  } finally {
    isFetching.value = false;
  }
};

const downloadPdf = async () => {
  if (!quote.value) return;
  isDownloading.value = true;
  try {
    const response = await QuotesAPI.downloadPdf(quote.value.id);
    downloadBlobFile(
      `cotizacion-${quote.value.lote || quote.value.id}.pdf`,
      response.data
    );
  } catch (error) {
    useAlert(t('QUOTES.ERRORS.DOWNLOAD'));
  } finally {
    isDownloading.value = false;
  }
};

onMounted(fetchQuote);
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-4xl mx-auto pb-12">
      <div v-if="isFetching" class="flex justify-center py-12">
        <Spinner size="24" />
      </div>

      <template v-else-if="quote">
        <div class="flex items-center justify-between py-6">
          <div>
            <h1 class="text-xl font-semibold text-n-slate-12">
              {{
                t('QUOTES.DETAIL.TITLE', {
                  nombre: quote.nombre,
                  lote: quote.lote,
                })
              }}
            </h1>
            <p class="text-sm text-n-slate-11">{{ quote.desarrollo }}</p>
          </div>
          <Button
            v-if="quote.pdf_attached"
            size="sm"
            variant="outline"
            icon="i-lucide-download"
            :is-loading="isDownloading"
            :label="t('QUOTES.TABLE.DOWNLOAD_PDF')"
            @click="downloadPdf"
          />
        </div>

        <p v-if="quote.status === 'failed'" class="text-n-ruby-11 text-sm mb-4">
          {{ quote.error_message }}
        </p>

        <div class="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-8">
          <div class="border border-n-weak rounded-lg p-3">
            <p class="text-xs text-n-slate-10">
              {{ t('QUOTES.DETAIL.PLAZOS') }}
            </p>
            <p class="text-n-slate-12 font-medium">{{ quote.plazos }}</p>
          </div>
          <div class="border border-n-weak rounded-lg p-3">
            <p class="text-xs text-n-slate-10">
              {{ t('QUOTES.DETAIL.ENGANCHE') }}
            </p>
            <p class="text-n-slate-12 font-medium">
              {{
                t('QUOTES.DETAIL.ENGANCHE_VALUE', {
                  pct: percent(quote.enganche_pct),
                  monto: currency(quote.enganche_monto),
                })
              }}
            </p>
          </div>
          <div class="border border-n-weak rounded-lg p-3">
            <p class="text-xs text-n-slate-10">
              {{ t('QUOTES.DETAIL.INTERES') }}
            </p>
            <p class="text-n-slate-12 font-medium">
              {{ percent(quote.interes_pct) }}
            </p>
          </div>
          <div class="border border-n-weak rounded-lg p-3">
            <p class="text-xs text-n-slate-10">
              {{ t('QUOTES.DETAIL.PRECIO_TOTAL') }}
            </p>
            <p class="text-n-slate-12 font-medium">
              {{ currency(quote.precio_total) }}
            </p>
          </div>
        </div>

        <h2 class="text-sm font-semibold text-n-slate-12 mb-2">
          {{ t('QUOTES.DETAIL.SCHEDULE_TITLE') }}
        </h2>
        <div class="border border-n-weak rounded-lg overflow-hidden mb-8">
          <table class="w-full text-sm">
            <thead class="bg-n-slate-2 text-n-slate-11">
              <tr>
                <th class="text-start px-3 py-2">
                  {{ t('QUOTES.DETAIL.PERIODO') }}
                </th>
                <th class="text-start px-3 py-2">
                  {{ t('QUOTES.DETAIL.FECHA') }}
                </th>
                <th class="text-end px-3 py-2">
                  {{ t('QUOTES.DETAIL.SALDO_INICIAL') }}
                </th>
                <th class="text-end px-3 py-2">
                  {{ t('QUOTES.DETAIL.INTERES_COL') }}
                </th>
                <th class="text-end px-3 py-2">
                  {{ t('QUOTES.DETAIL.CAPITAL') }}
                </th>
                <th class="text-end px-3 py-2">
                  {{ t('QUOTES.DETAIL.PAGO') }}
                </th>
                <th class="text-end px-3 py-2">
                  {{ t('QUOTES.DETAIL.SALDO_FINAL') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in quote.schedule"
                :key="row.periodo"
                class="border-t border-n-weak"
              >
                <td class="px-3 py-1.5">{{ row.periodo }}</td>
                <td class="px-3 py-1.5">{{ row.fecha }}</td>
                <td class="px-3 py-1.5 text-end">
                  {{ currency(row.saldo_inicial) }}
                </td>
                <td class="px-3 py-1.5 text-end">
                  {{ currency(row.interes) }}
                </td>
                <td class="px-3 py-1.5 text-end">
                  {{ currency(row.capital) }}
                </td>
                <td class="px-3 py-1.5 text-end font-medium">
                  {{ currency(row.pago) }}
                </td>
                <td class="px-3 py-1.5 text-end">
                  {{ currency(row.saldo_final) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>
  </div>
</template>
