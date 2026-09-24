<script setup>
import { ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { useAlert } from 'dashboard/composables';
import { downloadBlobFile } from 'dashboard/helper/downloadHelper';
import QuotesAPI from 'dashboard/api/quotes';
import Spinner from 'shared/components/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import QuoteFieldsForm from '../components/QuoteFieldsForm.vue';
import { mapZohoProductToFields, productLabel } from '../helpers/productMapper';

const { t } = useI18n();
const router = useRouter();

const EMPTY_FIELDS = () => ({
  nombre: '',
  lote: '',
  desarrollo: '',
  color: '',
  superficie: '',
  precio_m2: '',
  plazos: '',
  enganche: '',
  interes: '',
  meses_sin_intereses: '',
  descuento: '',
  fecha_entrega: '',
});

const quotes = ref([]);
const isFetching = ref(false);
const downloadingId = ref(null);

const productQuery = ref('');
const productResults = ref([]);
const isSearchingProducts = ref(false);
const selectedProduct = ref(null);
const fields = ref(EMPTY_FIELDS());
const isGenerating = ref(false);
const generateError = ref(null);

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

const searchProducts = debounce(async () => {
  if (!productQuery.value.trim()) {
    productResults.value = [];
    return;
  }
  isSearchingProducts.value = true;
  try {
    const response = await QuotesAPI.searchProducts(productQuery.value.trim());
    productResults.value = response.data;
  } catch (error) {
    productResults.value = [];
  } finally {
    isSearchingProducts.value = false;
  }
}, 300);

const selectProduct = product => {
  selectedProduct.value = product;
  productResults.value = [];
  productQuery.value = productLabel(product);
  fields.value = { ...fields.value, ...mapZohoProductToFields(product) };
};

const clearProduct = () => {
  selectedProduct.value = null;
  productQuery.value = '';
  fields.value = EMPTY_FIELDS();
};

const generateQuote = async () => {
  if (!selectedProduct.value) return;
  isGenerating.value = true;
  generateError.value = null;
  try {
    const response = await QuotesAPI.create({
      zoho_product_id: selectedProduct.value.id,
      ...fields.value,
    });
    if (response.data.status === 'completed') {
      router.push({
        name: 'quotes_dashboard_show',
        params: { quoteId: response.data.id },
      });
    } else {
      generateError.value =
        response.data.error_message || t('QUOTES.ERRORS.GENERATE');
    }
  } catch (error) {
    generateError.value =
      error.response?.data?.error || t('QUOTES.ERRORS.GENERATE');
  } finally {
    isGenerating.value = false;
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

      <div class="border border-n-weak rounded-lg p-4 mb-6">
        <p class="text-sm font-medium text-n-slate-12 mb-2">
          {{ t('QUOTES.GENERATE.TITLE') }}
        </p>

        <div class="relative max-w-sm mb-4">
          <Input
            v-model="productQuery"
            class="mb-0"
            :placeholder="t('QUOTES.GENERATE.PRODUCT_PLACEHOLDER')"
            :disabled="isGenerating"
            @input="searchProducts"
          />
          <button
            v-if="selectedProduct"
            type="button"
            class="absolute end-2 top-2 text-xs text-n-slate-10 hover:text-n-slate-12"
            @click="clearProduct"
          >
            {{ t('QUOTES.GENERATE.CLEAR_PRODUCT') }}
          </button>
          <div
            v-if="productResults.length"
            class="absolute z-10 mt-1 w-full bg-n-solid-2 border border-n-weak rounded-lg shadow-lg max-h-56 overflow-auto"
          >
            <button
              v-for="product in productResults"
              :key="product.id"
              type="button"
              class="w-full text-start px-3 py-2 text-sm hover:bg-n-slate-3"
              @click="selectProduct(product)"
            >
              {{ productLabel(product) }}
            </button>
          </div>
          <p v-if="isSearchingProducts" class="text-xs text-n-slate-10 mt-1">
            {{ t('QUOTES.GENERATE.SEARCHING') }}
          </p>
        </div>

        <template v-if="selectedProduct">
          <QuoteFieldsForm v-model="fields" :disabled="isGenerating" />
          <Button
            class="mt-4"
            size="sm"
            :is-loading="isGenerating"
            :label="t('QUOTES.GENERATE.SUBMIT')"
            @click="generateQuote"
          />
        </template>

        <p v-if="generateError" class="text-n-ruby-11 text-xs mt-2">
          {{ generateError }}
        </p>
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
