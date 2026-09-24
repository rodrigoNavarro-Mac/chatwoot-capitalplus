<script setup>
import { ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { downloadBlobFile } from 'dashboard/helper/downloadHelper';
import QuotesAPI from 'dashboard/api/quotes';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();

const quotes = ref([]);
const isFetching = ref(false);
const downloadingId = ref(null);

const statusClass = status => {
  if (status === 'completed') return 'bg-n-teal-3 text-n-teal-11';
  if (status === 'failed') return 'bg-n-ruby-3 text-n-ruby-11';
  return 'bg-n-amber-3 text-n-amber-11';
};

const currency = value =>
  Number(value || 0).toLocaleString('es-MX', {
    style: 'currency',
    currency: 'MXN',
  });

const fetchQuotes = async () => {
  isFetching.value = true;
  try {
    const response = await QuotesAPI.get();
    quotes.value = response.data;
  } catch (error) {
    useAlert(t('QUOTES.ERRORS.FETCH'));
  } finally {
    isFetching.value = false;
  }
};

const downloadPdf = async quote => {
  downloadingId.value = quote.id;
  try {
    const response = await QuotesAPI.downloadPdf(quote.id);
    downloadBlobFile(`cotizacion-${quote.lote || quote.id}.pdf`, response.data);
  } catch (error) {
    useAlert(t('QUOTES.ERRORS.DOWNLOAD'));
  } finally {
    downloadingId.value = null;
  }
};

onMounted(fetchQuotes);
</script>

<template>
  <div class="overflow-auto bg-n-surface-1 w-full px-6">
    <div class="max-w-6xl mx-auto pb-12">
      <div class="flex items-center justify-between py-6">
        <div>
          <h1 class="text-xl font-semibold text-n-slate-12">
            {{ t('QUOTES.HEADER') }}
          </h1>
          <p class="text-sm text-n-slate-11">
            {{ t('QUOTES.DESCRIPTION') }}
          </p>
        </div>
      </div>

      <div v-if="isFetching" class="flex justify-center py-12">
        <Spinner size="24" />
      </div>

      <p v-else-if="!quotes.length" class="text-sm text-n-slate-10 py-12">
        {{ t('QUOTES.EMPTY') }}
      </p>

      <div v-else class="border border-n-weak rounded-lg overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-n-slate-2 text-n-slate-11">
            <tr>
              <th class="text-start px-4 py-2">{{ t('QUOTES.TABLE.LOTE') }}</th>
              <th class="text-start px-4 py-2">
                {{ t('QUOTES.TABLE.DESARROLLO') }}
              </th>
              <th class="text-start px-4 py-2">
                {{ t('QUOTES.TABLE.PRECIO_TOTAL') }}
              </th>
              <th class="text-start px-4 py-2">
                {{ t('QUOTES.TABLE.STATUS') }}
              </th>
              <th class="text-start px-4 py-2">
                {{ t('QUOTES.TABLE.CREATED_AT') }}
              </th>
              <th class="text-end px-4 py-2">
                {{ t('QUOTES.TABLE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="quote in quotes"
              :key="quote.id"
              class="border-t border-n-weak"
            >
              <td class="px-4 py-2 text-n-slate-12 font-medium">
                {{ quote.lote || '-' }}
              </td>
              <td class="px-4 py-2 text-n-slate-11">
                {{ quote.desarrollo || '-' }}
              </td>
              <td class="px-4 py-2 text-n-slate-12">
                {{ currency(quote.precio_total) }}
              </td>
              <td class="px-4 py-2">
                <span
                  class="px-2 py-0.5 rounded-full text-xs font-medium"
                  :class="statusClass(quote.status)"
                >
                  {{ quote.status }}
                </span>
              </td>
              <td class="px-4 py-2 text-n-slate-11">
                {{ new Date(quote.created_at).toLocaleDateString('es-MX') }}
              </td>
              <td class="px-4 py-2 text-end">
                <RouterLink
                  :to="{
                    name: 'quotes_dashboard_show',
                    params: { quoteId: quote.id },
                  }"
                  class="text-xs font-medium text-n-brand hover:underline me-3"
                >
                  {{ t('QUOTES.TABLE.VIEW') }}
                </RouterLink>
                <Button
                  v-if="quote.pdf_attached"
                  size="xs"
                  variant="outline"
                  icon="i-lucide-download"
                  :is-loading="downloadingId === quote.id"
                  @click="downloadPdf(quote)"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>
