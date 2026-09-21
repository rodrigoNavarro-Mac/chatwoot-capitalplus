<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import RevenueIntelligenceAPI from 'dashboard/api/revenueIntelligence';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

// filterOptions: árbol campaña -> adset -> advert SIEMPRE completo, ver
// V2::Reports::RevenueIntelligenceBuilder#marketing_filter_options -- el usuario elige de los
// nombres ya existentes (nunca escribe a mano, sección 10.4 del brief de Marketing) porque nunca
// hay un id real de Meta que ligar por escritura libre (ver Fase 1 de la auditoría).
const props = defineProps({
  filterOptions: { type: Array, default: () => [] },
});

const emit = defineEmits(['saved']);

const { t } = useI18n();

const dialogRef = ref(null);
const isLoading = ref(false);
const editingId = ref(null);
const overlapWarning = ref(null);
const serverErrors = ref(null);

const emptyForm = () => ({
  campaignName: '',
  adsetName: '',
  advertName: '',
  periodStart: '',
  periodEnd: '',
  amount: '',
});
const form = ref(emptyForm());

const campaignOptions = computed(() =>
  props.filterOptions.map(campaign => ({
    value: campaign.id,
    label: campaign.id,
  }))
);
const selectedCampaign = computed(() =>
  props.filterOptions.find(campaign => campaign.id === form.value.campaignName)
);
const adsetOptions = computed(() =>
  (selectedCampaign.value?.adsets ?? []).map(adset => ({
    value: adset.id,
    label: adset.name || adset.id,
  }))
);
const selectedAdset = computed(() =>
  (selectedCampaign.value?.adsets ?? []).find(
    adset => adset.id === form.value.adsetName
  )
);
const advertOptions = computed(() =>
  (selectedAdset.value?.adverts ?? []).map(advert => ({
    value: advert.id,
    label: advert.name || advert.id,
  }))
);

// Cambiar de campaña/adset invalida las selecciones más profundas -- un adset de OTRA campaña no
// tiene sentido quedarse seleccionado (sección 10.4: la captura sigue la jerarquía real).
const onCampaignChange = () => {
  form.value.adsetName = '';
  form.value.advertName = '';
};
const onAdsetChange = () => {
  form.value.advertName = '';
};

const isEditing = computed(() => !!editingId.value);
const canSave = computed(
  () =>
    !!form.value.campaignName &&
    !!form.value.periodStart &&
    !!form.value.periodEnd &&
    form.value.amount !== '' &&
    Number(form.value.amount) >= 0
);

const open = (adSpend = null) => {
  form.value = emptyForm();
  editingId.value = adSpend?.id || null;
  overlapWarning.value = null;
  serverErrors.value = null;
  if (adSpend) {
    form.value = {
      campaignName: adSpend.campaign_name,
      adsetName: adSpend.adset_name || '',
      advertName: adSpend.advert_name || '',
      periodStart: adSpend.period_start,
      periodEnd: adSpend.period_end,
      amount: adSpend.amount,
    };
  }
  dialogRef.value?.open();
};

const buildPayload = () => ({
  campaign_name: form.value.campaignName,
  adset_name: form.value.adsetName || null,
  advert_name: form.value.advertName || null,
  period_start: form.value.periodStart,
  period_end: form.value.periodEnd,
  amount: form.value.amount,
});

const save = async (force = false) => {
  if (!canSave.value) return;

  isLoading.value = true;
  overlapWarning.value = null;
  serverErrors.value = null;
  try {
    const payload = buildPayload();
    const response = isEditing.value
      ? await RevenueIntelligenceAPI.updateAdSpend(
          editingId.value,
          payload,
          force
        )
      : await RevenueIntelligenceAPI.createAdSpend(payload, force);
    useAlert(t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.SUCCESS'));
    emit('saved', response.data);
    dialogRef.value?.close();
  } catch (error) {
    if (error?.response?.status === 409) {
      overlapWarning.value = error.response.data;
    } else if (error?.response?.status === 422) {
      serverErrors.value = error.response.data;
    } else {
      useAlert(t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.ERROR'));
    }
  } finally {
    isLoading.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    :title="
      t(
        isEditing
          ? 'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.EDIT_TITLE'
          : 'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.TITLE'
      )
    "
    width="md"
    :is-loading="isLoading"
    :disable-confirm-button="!canSave"
    :confirm-button-label="
      t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.SAVE')
    "
    :cancel-button-label="
      t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.CANCEL')
    "
    @confirm="save(false)"
  >
    <div class="flex flex-col gap-4">
      <div>
        <label class="text-sm text-n-slate-11 mb-1 block">
          {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.CAMPAIGN') }}
        </label>
        <Select
          v-model="form.campaignName"
          :options="campaignOptions"
          class="w-full"
          @update:model-value="onCampaignChange"
        />
      </div>
      <div>
        <label class="text-sm text-n-slate-11 mb-1 block">
          {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.ADSET') }}
        </label>
        <Select
          v-model="form.adsetName"
          :options="adsetOptions"
          :disabled="!form.campaignName"
          class="w-full"
          @update:model-value="onAdsetChange"
        />
      </div>
      <div>
        <label class="text-sm text-n-slate-11 mb-1 block">
          {{ t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.ADVERT') }}
        </label>
        <Select
          v-model="form.advertName"
          :options="advertOptions"
          :disabled="!form.adsetName"
          class="w-full"
        />
      </div>
      <div class="flex gap-3">
        <Input
          v-model="form.periodStart"
          type="date"
          class="w-full"
          :label="
            t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.PERIOD_START')
          "
        />
        <Input
          v-model="form.periodEnd"
          type="date"
          class="w-full"
          :label="
            t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.PERIOD_END')
          "
        />
      </div>
      <Input
        v-model="form.amount"
        type="number"
        min="0"
        :label="t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.AMOUNT')"
      />
      <div
        v-if="overlapWarning"
        class="p-3 rounded-lg bg-n-amber-3 text-n-amber-11 text-sm flex flex-col gap-2"
      >
        <span>{{
          t(
            'REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.OVERLAP_WARNING'
          )
        }}</span>
        <button
          type="button"
          class="self-start underline cursor-pointer bg-transparent border-0 p-0 text-n-amber-11"
          @click="save(true)"
        >
          {{
            t('REVENUE_INTELLIGENCE_REPORTS.MARKETING.SPEND_MODAL.SAVE_ANYWAY')
          }}
        </button>
      </div>
      <div
        v-if="serverErrors"
        class="p-3 rounded-lg bg-n-ruby-3 text-n-ruby-11 text-sm"
      >
        {{ Object.values(serverErrors).flat().join(', ') }}
      </div>
    </div>
  </Dialog>
</template>
