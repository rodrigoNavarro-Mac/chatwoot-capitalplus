<script setup>
import { reactive, computed, watch, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';
import CampaignsAPI from 'dashboard/api/campaigns';
import { timeZoneOptions } from 'dashboard/routes/dashboard/settings/inbox/helpers/businessHour.js';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

const props = defineProps({
  selectedCampaign: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['submit', 'cancel']);

const { t } = useI18n();

const formState = {
  uiFlags: useMapGetter('campaigns/getUIFlags'),
  labels: useMapGetter('labels/getLabels'),
  inboxes: useMapGetter('inboxes/getWhatsAppInboxes'),
  getFilteredWhatsAppTemplates: useMapGetter(
    'inboxes/getFilteredWhatsAppTemplates'
  ),
};

const initialState = {
  title: '',
  inboxId: null,
  templateId: null,
  scheduledAt: null,
  selectedAudience: [],
  audienceType: 'labels',
  delayMinSeconds: 300,
  delayMaxSeconds: 420,
  sendWindowStart: '09:00',
  sendWindowEnd: '19:00',
  timezone: 'UTC',
};

const state = reactive({ ...initialState });
const csvFile = ref(null);
const hasAttemptedSubmit = ref(false);
const templateParserRef = ref(null);
const csvPreview = ref(null);
const isPreviewingCsv = ref(false);
let csvPreviewToken = 0;

const isEditMode = computed(() => !!props.selectedCampaign);

const rules = computed(() => ({
  title: { required, minLength: minLength(1) },
  inboxId: { required },
  templateId: { required },
  scheduledAt: { required },
  selectedAudience: state.audienceType === 'labels' ? { required } : {},
}));

const v$ = useVuelidate(rules, state);

const isCreating = computed(() => formState.uiFlags.value.isCreating);
const isUpdating = computed(() => formState.uiFlags.value.isUpdating);
const isBusy = computed(() => isCreating.value || isUpdating.value);

// In edit mode, the campaign may already have a CSV attached server-side (has_csv_audience)
// — a <input type="file"> can never be pre-filled with it, so re-uploading must stay optional
// or every edit (even just the send window) would be blocked on re-attaching the same file.
const hasExistingCsvAudience = computed(
  () => isEditMode.value && !!props.selectedCampaign?.has_csv_audience
);

const csvAudienceError = computed(
  () =>
    hasAttemptedSubmit.value &&
    state.audienceType === 'csv' &&
    !csvFile.value &&
    !hasExistingCsvAudience.value
);

const currentDateTime = computed(() => {
  const now = new Date();
  const localTime = new Date(now.getTime() - now.getTimezoneOffset() * 60000);
  return localTime.toISOString().slice(0, 16);
});

const mapToOptions = (items, valueKey, labelKey) =>
  items?.map(item => ({
    value: item[valueKey],
    label: item[labelKey],
  })) ?? [];

const audienceList = computed(() =>
  mapToOptions(formState.labels.value, 'id', 'title')
);

const inboxOptions = computed(() =>
  mapToOptions(formState.inboxes.value, 'id', 'name')
);

const timeZoneOptionsList = computed(() => timeZoneOptions());

const templateOptions = computed(() => {
  if (!state.inboxId) return [];
  const templates = formState.getFilteredWhatsAppTemplates.value(state.inboxId);
  return templates.map(template => {
    const friendlyName = template.name
      .replace(/_/g, ' ')
      .replace(/\b\w/g, l => l.toUpperCase());

    return {
      value: template.id,
      label: `${friendlyName} (${template.language || 'en'})`,
      template: template,
    };
  });
});

const selectedTemplate = computed(() => {
  if (!state.templateId) return null;
  return templateOptions.value.find(option => option.value === state.templateId)
    ?.template;
});

const getErrorMessage = (field, errorKey) => {
  const baseKey = 'CAMPAIGN.WHATSAPP.CREATE.FORM';
  return v$.value[field].$error ? t(`${baseKey}.${errorKey}.ERROR`) : '';
};

const formErrors = computed(() => ({
  title: getErrorMessage('title', 'TITLE'),
  inbox: getErrorMessage('inboxId', 'INBOX'),
  template: getErrorMessage('templateId', 'TEMPLATE'),
  scheduledAt: getErrorMessage('scheduledAt', 'SCHEDULED_AT'),
  audience:
    state.audienceType === 'labels'
      ? getErrorMessage('selectedAudience', 'AUDIENCE')
      : '',
}));

const hasRequiredTemplateParams = computed(() => {
  return templateParserRef.value?.isFormInvalid === false;
});

const isSubmitDisabled = computed(() => {
  if (v$.value.$invalid) return true;
  if (state.audienceType === 'csv') {
    if (!csvFile.value && !hasExistingCsvAudience.value) return true;
    if (isPreviewingCsv.value) return true;
    if (
      csvPreview.value &&
      (!csvPreview.value.valid || !csvPreview.value.valid_count)
    ) {
      return true;
    }
  }
  return !hasRequiredTemplateParams.value;
});

const formatToUTCString = localDateTime =>
  localDateTime ? new Date(localDateTime).toISOString() : null;

const timestampToLocalDatetimeString = timestamp => {
  if (!timestamp) return null;
  const date = new Date(timestamp * 1000);
  const localTime = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
  return localTime.toISOString().slice(0, 16);
};

const resetState = () => {
  Object.assign(state, initialState);
  csvFile.value = null;
  csvPreview.value = null;
  hasAttemptedSubmit.value = false;
  v$.value.$reset();
};

// Pre-populate form when in edit mode
watch(
  () => props.selectedCampaign,
  campaign => {
    if (!campaign) return;
    state.title = campaign.title ?? '';
    state.inboxId = campaign.inbox?.id ?? null;
    state.selectedAudience = campaign.audience?.map(a => a.id) ?? [];
    state.audienceType = campaign.audience_type ?? 'labels';
    state.scheduledAt = timestampToLocalDatetimeString(campaign.scheduled_at);
    state.delayMinSeconds = campaign.delay_min_seconds ?? 300;
    state.delayMaxSeconds = campaign.delay_max_seconds ?? 420;
    state.sendWindowStart = campaign.send_window_start ?? '09:00';
    state.sendWindowEnd = campaign.send_window_end ?? '19:00';
    state.timezone = campaign.timezone ?? 'UTC';
  },
  { immediate: true }
);

// After inbox is set and templates load, match templateId by name
watch(templateOptions, options => {
  if (!props.selectedCampaign?.template_params?.name) return;
  if (state.templateId) return;
  const match = options.find(
    o => o.template?.name === props.selectedCampaign.template_params.name
  );
  if (match) state.templateId = match.value;
});

const handleCancel = () => emit('cancel');

const previewCsvFile = async file => {
  csvPreviewToken += 1;
  const token = csvPreviewToken;
  isPreviewingCsv.value = true;
  csvPreview.value = null;
  try {
    const response = await CampaignsAPI.previewCsv(file);
    if (token !== csvPreviewToken) return;
    csvPreview.value = response.data;
  } catch (error) {
    if (token !== csvPreviewToken) return;
    csvPreview.value = {
      valid: false,
      errors: [t('CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.PREVIEW.ERROR')],
    };
  } finally {
    if (token === csvPreviewToken) isPreviewingCsv.value = false;
  }
};

const handleCsvFileChange = event => {
  const file = event.target.files[0] || null;
  csvFile.value = file;
  csvPreview.value = null;
  if (file) previewCsvFile(file);
};

const setAudienceType = type => {
  state.audienceType = type;
  if (type === 'csv') {
    state.selectedAudience = [];
  } else {
    csvFile.value = null;
    csvPreview.value = null;
  }
};

const prepareCampaignDetails = () => {
  const currentTemplate = selectedTemplate.value;
  const parserData = templateParserRef.value;
  const templateContent = parserData?.renderedTemplate || '';

  const templateParams = {
    name: currentTemplate?.name || '',
    namespace: currentTemplate?.namespace || '',
    category: currentTemplate?.category || 'UTILITY',
    language: currentTemplate?.language || 'en_US',
    processed_params: parserData?.processedParams || {},
  };

  return {
    title: state.title,
    message: templateContent,
    template_params: templateParams,
    inbox_id: state.inboxId,
    scheduled_at: formatToUTCString(state.scheduledAt),
    audience_type: state.audienceType,
    audience:
      state.audienceType === 'labels'
        ? (state.selectedAudience?.map(id => ({ id, type: 'Label' })) ?? [])
        : [],
    delay_min_seconds: state.delayMinSeconds,
    delay_max_seconds: state.delayMaxSeconds,
    send_window_start: state.sendWindowStart,
    send_window_end: state.sendWindowEnd,
    timezone: state.timezone,
  };
};

const handleSubmit = async () => {
  hasAttemptedSubmit.value = true;

  if (state.audienceType === 'csv' && !csvFile.value) return;

  const isFormValid = await v$.value.$validate();
  if (!isFormValid || !hasRequiredTemplateParams.value) return;

  emit('submit', prepareCampaignDetails(), csvFile.value || null);
  if (!isEditMode.value) {
    resetState();
    handleCancel();
  }
};

// Reset template selection when inbox changes (only in create mode)
watch(
  () => state.inboxId,
  (newVal, oldVal) => {
    if (oldVal !== null) state.templateId = null;
  }
);

defineExpose({ prepareCampaignDetails, isSubmitDisabled });
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <Input
      v-model="state.title"
      :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TITLE.LABEL')"
      :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TITLE.PLACEHOLDER')"
      :message="formErrors.title"
      :message-type="formErrors.title ? 'error' : 'info'"
    />

    <div class="flex flex-col gap-1">
      <label for="inbox" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.INBOX.LABEL') }}
      </label>
      <ComboBox
        id="inbox"
        v-model="state.inboxId"
        :options="inboxOptions"
        :has-error="!!formErrors.inbox"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.INBOX.PLACEHOLDER')"
        :message="formErrors.inbox"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="template" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.LABEL') }}
      </label>
      <ComboBox
        id="template"
        v-model="state.templateId"
        :options="templateOptions"
        :has-error="!!formErrors.template"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.PLACEHOLDER')"
        :message="formErrors.template"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
      <p class="mt-1 text-xs text-n-slate-11">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.INFO') }}
      </p>
    </div>

    <!-- Template Parser -->
    <WhatsAppTemplateParser
      v-if="selectedTemplate"
      ref="templateParserRef"
      :template="selectedTemplate"
      :inbox-id="state.inboxId"
      autofill-name-variable
    />

    <!-- Audience type toggle -->
    <div class="flex flex-col gap-1">
      <label class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_TYPE.LABEL') }}
      </label>
      <div class="flex rounded-lg overflow-hidden border border-n-weak">
        <button
          type="button"
          class="flex-1 py-1.5 text-sm font-medium transition-colors"
          :class="
            state.audienceType === 'labels'
              ? 'bg-n-blue-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="setAudienceType('labels')"
        >
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_TYPE.LABELS') }}
        </button>
        <button
          type="button"
          class="flex-1 py-1.5 text-sm font-medium transition-colors"
          :class="
            state.audienceType === 'csv'
              ? 'bg-n-blue-9 text-white'
              : 'text-n-slate-11 hover:bg-n-alpha-2'
          "
          @click="setAudienceType('csv')"
        >
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE_TYPE.CSV') }}
        </button>
      </div>
    </div>

    <!-- Label audience -->
    <div v-show="state.audienceType === 'labels'" class="flex flex-col gap-1">
      <label for="audience" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL') }}
      </label>
      <TagMultiSelectComboBox
        v-model="state.selectedAudience"
        :options="audienceList"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL')"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.PLACEHOLDER')"
        :has-error="!!formErrors.audience"
        :message="formErrors.audience"
        class="[&>div>button]:bg-n-alpha-black2"
      />
    </div>

    <!-- CSV audience -->
    <div v-show="state.audienceType === 'csv'" class="flex flex-col gap-1">
      <label class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.LABEL') }}
      </label>
      <label
        class="flex items-center gap-2 px-3 py-2 rounded-lg border cursor-pointer text-sm transition-colors"
        :class="
          csvAudienceError
            ? 'border-n-red-8 bg-n-alpha-black2'
            : 'border-n-weak bg-n-alpha-black2 hover:bg-n-alpha-3'
        "
      >
        <input
          type="file"
          accept=".csv"
          class="hidden"
          @change="handleCsvFileChange"
        />
        <span v-if="csvFile" class="text-n-slate-12 truncate">
          {{ csvFile.name }}
        </span>
        <span
          v-else-if="hasExistingCsvAudience"
          class="text-n-slate-12 truncate"
        >
          {{ t('CAMPAIGN.WHATSAPP_EDIT.FORM.CSV_AUDIENCE.EXISTING_FILE') }}
        </span>
        <span v-else class="text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.PLACEHOLDER') }}
        </span>
      </label>
      <p class="mt-1 text-xs text-n-slate-11">
        {{
          hasExistingCsvAudience && !csvFile
            ? t('CAMPAIGN.WHATSAPP_EDIT.FORM.CSV_AUDIENCE.REPLACE_INFO')
            : t('CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.INFO')
        }}
      </p>
      <p v-if="csvAudienceError" class="mt-1 text-xs text-n-red-9">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.ERROR') }}
      </p>

      <div
        v-if="isPreviewingCsv"
        class="flex items-center gap-2 mt-1 text-xs text-n-slate-11"
      >
        <Spinner :size="14" />
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.PREVIEW.CHECKING') }}
      </div>

      <div
        v-else-if="csvPreview && !csvPreview.valid"
        class="flex flex-col gap-0.5 mt-1 text-xs text-n-red-9"
      >
        <p v-for="(error, index) in csvPreview.errors" :key="index">
          {{ error }}
        </p>
      </div>

      <div
        v-else-if="csvPreview"
        class="flex flex-col gap-0.5 mt-1 text-xs"
        :class="csvPreview.valid_count ? 'text-n-slate-11' : 'text-n-red-9'"
      >
        <p v-if="csvPreview.valid_count" class="text-n-teal-11 font-medium">
          {{
            t('CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.PREVIEW.SUMMARY', {
              valid: csvPreview.valid_count,
              total: csvPreview.total_rows,
            })
          }}
        </p>
        <p v-else>
          {{
            t(
              'CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.PREVIEW.NO_VALID_ROWS'
            )
          }}
        </p>
        <p v-if="csvPreview.missing_phone_count">
          {{
            t(
              'CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.PREVIEW.MISSING_PHONE',
              { count: csvPreview.missing_phone_count }
            )
          }}
        </p>
        <p v-if="csvPreview.duplicate_count">
          {{
            t('CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.PREVIEW.DUPLICATE', {
              count: csvPreview.duplicate_count,
            })
          }}
        </p>
        <p v-if="csvPreview.already_bounced_count">
          {{
            t(
              'CAMPAIGN.WHATSAPP.CREATE.FORM.CSV_AUDIENCE.PREVIEW.ALREADY_BOUNCED',
              { count: csvPreview.already_bounced_count }
            )
          }}
        </p>
      </div>
    </div>

    <Input
      v-model="state.scheduledAt"
      :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.SCHEDULED_AT.LABEL')"
      type="datetime-local"
      :min="currentDateTime"
      :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.SCHEDULED_AT.PLACEHOLDER')"
      :message="formErrors.scheduledAt"
      :message-type="formErrors.scheduledAt ? 'error' : 'info'"
    />

    <div class="flex gap-3">
      <Input
        v-model="state.sendWindowStart"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEND_WINDOW_START.LABEL')"
        type="time"
        class="flex-1"
      />
      <Input
        v-model="state.sendWindowEnd"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.SEND_WINDOW_END.LABEL')"
        type="time"
        class="flex-1"
      />
    </div>

    <div class="flex flex-col gap-1">
      <label for="timezone" class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.TIMEZONE.LABEL') }}
      </label>
      <ComboBox
        id="timezone"
        v-model="state.timezone"
        :options="timeZoneOptionsList"
        :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TIMEZONE.PLACEHOLDER')"
        class="[&>div>button]:bg-n-alpha-black2 [&>div>button:not(.focused)]:dark:outline-n-weak [&>div>button:not(.focused)]:hover:!outline-n-slate-6"
      />
    </div>

    <div class="flex gap-3">
      <Input
        v-model.number="state.delayMinSeconds"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.DELAY_MIN.LABEL')"
        type="number"
        min="60"
        class="flex-1"
      />
      <Input
        v-model.number="state.delayMaxSeconds"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.DELAY_MAX.LABEL')"
        type="number"
        min="60"
        class="flex-1"
      />
    </div>

    <div
      v-if="!isEditMode"
      class="flex gap-3 justify-between items-center w-full"
    >
      <Button
        variant="faded"
        color="slate"
        type="button"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.BUTTONS.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-11 hover:bg-n-alpha-3"
        @click="handleCancel"
      />
      <Button
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.BUTTONS.CREATE')"
        class="w-full"
        type="submit"
        :is-loading="isBusy"
        :disabled="isBusy || isSubmitDisabled"
      />
    </div>
  </form>
</template>
