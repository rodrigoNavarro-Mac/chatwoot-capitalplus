<script setup>
import { reactive, ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import {
  buildTemplateParameters,
  findComponentByType,
  COMPONENT_TYPES,
  MEDIA_FORMATS,
} from 'dashboard/helper/templateHelper';

const props = defineProps({
  step: { type: Object, required: true },
  index: { type: Number, required: true },
  inboxId: { type: [Number, String], required: true },
});

const emit = defineEmits(['save', 'delete']);

const { t } = useI18n();

const MANUAL_OPTION_VALUE = '__manual__';
const templateOptionValue = tpl => `${tpl.name}|||${tpl.language}`;

const getFilteredWhatsAppTemplates = useMapGetter(
  'inboxes/getFilteredWhatsAppTemplates'
);
const availableTemplates = computed(
  () => getFilteredWhatsAppTemplates.value(props.inboxId) || []
);

const form = reactive({
  label: props.step.label || '',
  template_name: props.step.template_name || '',
  template_language: props.step.template_language || 'es_MX',
  template_namespace: props.step.template_namespace || '',
  schedule_type: props.step.schedule_type || 'immediate',
  offset_minutes: props.step.offset_minutes,
  day_offset: props.step.day_offset,
  time_of_day: props.step.time_of_day || '',
  wait_window_minutes: props.step.wait_window_minutes,
  creates_call_task: !!props.step.creates_call_task,
  active: props.step.active !== false,
  media_type: props.step.media_type || '',
  media_url: props.step.media_url || '',
  media_name: props.step.media_name || '',
  body_variables: { ...(props.step.body_variables || {}) },
});

const initialMatch = availableTemplates.value.find(
  tpl =>
    tpl.name === props.step.template_name &&
    tpl.language === props.step.template_language
);
const selectedTemplateKey = ref(
  initialMatch ? templateOptionValue(initialMatch) : MANUAL_OPTION_VALUE
);

const isManualMode = computed(
  () => selectedTemplateKey.value === MANUAL_OPTION_VALUE
);

const selectedTemplate = computed(() => {
  if (isManualMode.value) return null;
  return (
    availableTemplates.value.find(
      tpl => templateOptionValue(tpl) === selectedTemplateKey.value
    ) || null
  );
});

const templateOptions = computed(() => [
  { value: '', label: t('CADENCE.TEMPLATES_SETTINGS.PICK_TEMPLATE') },
  ...availableTemplates.value.map(tpl => ({
    value: templateOptionValue(tpl),
    label: `${tpl.name} (${tpl.language})`,
  })),
  {
    value: MANUAL_OPTION_VALUE,
    label: t('CADENCE.TEMPLATES_SETTINGS.MANUAL_TEMPLATE_OPTION'),
  },
]);

const headerComponent = computed(() =>
  selectedTemplate.value
    ? findComponentByType(selectedTemplate.value, COMPONENT_TYPES.HEADER)
    : null
);
const hasMediaHeader = computed(
  () =>
    !!headerComponent.value &&
    MEDIA_FORMATS.includes(headerComponent.value.format)
);

const bodyVariableKeys = computed(() => {
  if (!selectedTemplate.value) return [];
  const skeleton = buildTemplateParameters(
    selectedTemplate.value,
    hasMediaHeader.value
  );
  return Object.keys(skeleton.body || {});
});

// Al elegir una plantilla real del picklist: autocompleta nombre/idioma/namespace,
// detecta el tipo real de adjunto del header (ya no se elige a mano) y prepara un input
// por cada variable del cuerpo que la plantilla realmente tenga.
watch(
  selectedTemplate,
  tpl => {
    if (!tpl) return;

    form.template_name = tpl.name;
    form.template_language = tpl.language;
    form.template_namespace = tpl.namespace || '';

    if (hasMediaHeader.value) {
      form.media_type = headerComponent.value.format.toLowerCase();
    } else {
      form.media_type = '';
      form.media_url = '';
      form.media_name = '';
    }

    const nextBodyVariables = {};
    bodyVariableKeys.value.forEach(key => {
      nextBodyVariables[key] = form.body_variables[key] || '';
    });
    form.body_variables = nextBodyVariables;
  },
  { immediate: true }
);

const scheduleTypeOptions = computed(() => [
  {
    value: 'immediate',
    label: t('CADENCE.TEMPLATES_SETTINGS.SCHEDULE_TYPE.IMMEDIATE'),
  },
  {
    value: 'offset_from_last_step',
    label: t('CADENCE.TEMPLATES_SETTINGS.SCHEDULE_TYPE.OFFSET_FROM_LAST_STEP'),
  },
  {
    value: 'day_offset_at_time',
    label: t('CADENCE.TEMPLATES_SETTINGS.SCHEDULE_TYPE.DAY_OFFSET_AT_TIME'),
  },
]);

const manualMediaTypeOptions = computed(() => [
  { value: '', label: t('CADENCE.TEMPLATES_SETTINGS.MEDIA.NONE') },
  { value: 'image', label: t('CADENCE.TEMPLATES_SETTINGS.MEDIA.IMAGE') },
  { value: 'video', label: t('CADENCE.TEMPLATES_SETTINGS.MEDIA.VIDEO') },
  { value: 'document', label: t('CADENCE.TEMPLATES_SETTINGS.MEDIA.DOCUMENT') },
]);

const LIQUID_VARIABLE_HINTS = [
  '{{ contact.name }}',
  '{{ contact.first_name }}',
  '{{ contact.last_name }}',
  '{{ contact.email }}',
  '{{ contact.phone_number }}',
  '{{ agent.name }}',
  '{{ agent.email }}',
  '{{ inbox.name }}',
  '{{ account.name }}',
];

const insertLiquidHint = (key, hint) => {
  form.body_variables[key] = `${form.body_variables[key] || ''}${hint}`;
};

const isOffsetSchedule = computed(
  () => form.schedule_type === 'offset_from_last_step'
);
const isDayOffsetSchedule = computed(
  () => form.schedule_type === 'day_offset_at_time'
);
const hasMedia = computed(() =>
  isManualMode.value ? !!form.media_type : hasMediaHeader.value
);
const isDocumentMedia = computed(() =>
  isManualMode.value
    ? form.media_type === 'document'
    : headerComponent.value?.format === 'DOCUMENT'
);

const save = () => {
  emit('save', {
    label: form.label,
    template_name: form.template_name,
    template_language: form.template_language,
    template_namespace: form.template_namespace || null,
    schedule_type: form.schedule_type,
    offset_minutes: isOffsetSchedule.value ? form.offset_minutes : null,
    day_offset: isDayOffsetSchedule.value ? form.day_offset : null,
    time_of_day: isDayOffsetSchedule.value ? form.time_of_day : null,
    wait_window_minutes: form.wait_window_minutes,
    creates_call_task: form.creates_call_task,
    active: form.active,
    media_type: hasMedia.value ? form.media_type : null,
    media_url: hasMedia.value ? form.media_url : null,
    media_name: isDocumentMedia.value ? form.media_name : null,
    body_variables: form.body_variables,
  });
};
</script>

<template>
  <div
    class="flex flex-col gap-4 p-4 rounded-xl outline outline-1 -outline-offset-1 outline-n-weak"
    :class="{ 'opacity-60': !form.active }"
  >
    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-2">
        <span
          class="cadence-step-drag-handle cursor-grab text-n-slate-9 i-lucide-grip-vertical size-4"
        />
        <span class="text-heading-3 text-n-slate-12">
          {{
            t('CADENCE.TEMPLATES_SETTINGS.STEP_NUMBER', { number: index + 1 })
          }}
        </span>
      </div>
      <div class="flex items-center gap-3">
        <label class="flex items-center gap-2 text-sm text-n-slate-11">
          {{ t('CADENCE.TEMPLATES_SETTINGS.ACTIVE') }}
          <Switch v-model="form.active" />
        </label>
        <NextButton
          type="button"
          ghost
          ruby
          xs
          icon="i-lucide-trash-2"
          :label="t('CADENCE.TEMPLATES_SETTINGS.DELETE.BUTTON')"
          @click="emit('delete')"
        />
      </div>
    </div>

    <Input
      v-model="form.label"
      :label="t('CADENCE.TEMPLATES_SETTINGS.LABEL')"
      :placeholder="t('CADENCE.TEMPLATES_SETTINGS.LABEL_PLACEHOLDER')"
    />

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CADENCE.TEMPLATES_SETTINGS.TEMPLATE_SECTION') }}
      </span>
      <div class="flex flex-col gap-1">
        <label class="text-sm text-n-slate-11">
          {{ t('CADENCE.TEMPLATES_SETTINGS.PICK_TEMPLATE_LABEL') }}
        </label>
        <Select v-model="selectedTemplateKey" :options="templateOptions" />
      </div>

      <div v-if="isManualMode" class="grid grid-cols-1 md:grid-cols-2 gap-3">
        <Input
          v-model="form.template_name"
          :label="t('CADENCE.TEMPLATES_SETTINGS.TEMPLATE_NAME')"
        />
        <Input
          v-model="form.template_language"
          :label="t('CADENCE.TEMPLATES_SETTINGS.TEMPLATE_LANGUAGE')"
        />
      </div>
      <p v-else-if="selectedTemplate" class="text-xs text-n-slate-11">
        {{
          t('CADENCE.TEMPLATES_SETTINGS.TEMPLATE_SELECTED_HINT', {
            name: form.template_name,
            language: form.template_language,
          })
        }}
      </p>
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CADENCE.TEMPLATES_SETTINGS.SCHEDULE_SECTION') }}
      </span>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-3 items-end">
        <div class="flex flex-col gap-1">
          <label class="text-sm text-n-slate-11">
            {{ t('CADENCE.TEMPLATES_SETTINGS.SCHEDULE_TYPE.LABEL') }}
          </label>
          <Select v-model="form.schedule_type" :options="scheduleTypeOptions" />
        </div>
        <Input
          v-if="isOffsetSchedule"
          v-model="form.offset_minutes"
          type="number"
          min="1"
          :label="t('CADENCE.TEMPLATES_SETTINGS.OFFSET_MINUTES')"
        />
        <template v-if="isDayOffsetSchedule">
          <Input
            v-model="form.day_offset"
            type="number"
            min="0"
            :label="t('CADENCE.TEMPLATES_SETTINGS.DAY_OFFSET')"
          />
          <div class="flex flex-col gap-1">
            <label class="text-sm text-n-slate-11">
              {{ t('CADENCE.TEMPLATES_SETTINGS.TIME_OF_DAY') }}
            </label>
            <input
              v-model="form.time_of_day"
              type="time"
              class="rounded-lg border-0 outline-1 outline -outline-offset-1 outline-n-weak bg-n-surface-1 py-2 px-3 text-sm"
            />
          </div>
        </template>
        <Input
          v-model="form.wait_window_minutes"
          type="number"
          min="1"
          :label="t('CADENCE.TEMPLATES_SETTINGS.WAIT_WINDOW')"
        />
      </div>
      <label class="flex items-center gap-2 text-sm text-n-slate-11 mt-1">
        <Switch v-model="form.creates_call_task" />
        {{ t('CADENCE.TEMPLATES_SETTINGS.CREATES_CALL_TASK') }}
      </label>
    </div>

    <div class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CADENCE.TEMPLATES_SETTINGS.MEDIA.SECTION') }}
      </span>
      <template v-if="isManualMode">
        <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div class="flex flex-col gap-1">
            <label class="text-sm text-n-slate-11">
              {{ t('CADENCE.TEMPLATES_SETTINGS.MEDIA.TYPE_LABEL') }}
            </label>
            <Select
              v-model="form.media_type"
              :options="manualMediaTypeOptions"
            />
          </div>
          <Input
            v-if="hasMedia"
            v-model="form.media_url"
            type="url"
            class="md:col-span-2"
            :label="t('CADENCE.TEMPLATES_SETTINGS.MEDIA.URL_LABEL')"
            :placeholder="t('CADENCE.TEMPLATES_SETTINGS.MEDIA.URL_PLACEHOLDER')"
          />
          <Input
            v-if="isDocumentMedia"
            v-model="form.media_name"
            :label="t('CADENCE.TEMPLATES_SETTINGS.MEDIA.NAME_LABEL')"
          />
        </div>
      </template>
      <template v-else-if="hasMediaHeader">
        <p class="text-xs text-n-slate-11">
          {{
            t('CADENCE.TEMPLATES_SETTINGS.MEDIA.DETECTED_HINT', {
              type: form.media_type,
            })
          }}
        </p>
        <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
          <Input
            v-model="form.media_url"
            type="url"
            class="md:col-span-2"
            :label="t('CADENCE.TEMPLATES_SETTINGS.MEDIA.URL_LABEL')"
            :placeholder="t('CADENCE.TEMPLATES_SETTINGS.MEDIA.URL_PLACEHOLDER')"
          />
          <Input
            v-if="isDocumentMedia"
            v-model="form.media_name"
            :label="t('CADENCE.TEMPLATES_SETTINGS.MEDIA.NAME_LABEL')"
          />
        </div>
      </template>
      <p v-else class="text-xs text-n-slate-11">
        {{ t('CADENCE.TEMPLATES_SETTINGS.MEDIA.NOT_APPLICABLE') }}
      </p>
    </div>

    <div v-if="bodyVariableKeys.length" class="flex flex-col gap-3">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('CADENCE.TEMPLATES_SETTINGS.BODY_VARIABLES.SECTION') }}
      </span>
      <div
        v-for="key in bodyVariableKeys"
        :key="key"
        class="flex flex-col gap-1"
      >
        <Input
          v-model="form.body_variables[key]"
          :label="
            t('CADENCE.TEMPLATES_SETTINGS.BODY_VARIABLES.VARIABLE_LABEL', {
              key,
            })
          "
          placeholder="{{ contact.name }}"
        />
        <p class="text-xs text-n-slate-11">
          {{ t('CADENCE.TEMPLATES_SETTINGS.BODY_VARIABLES.LIQUID_HINT_INTRO') }}
        </p>
        <div class="flex flex-wrap gap-1">
          <button
            v-for="hint in LIQUID_VARIABLE_HINTS"
            :key="hint"
            type="button"
            class="px-1.5 py-0.5 rounded text-xs font-mono bg-n-slate-3 text-n-slate-11 hover:bg-n-slate-4"
            @click="insertLiquidHint(key, hint)"
          >
            {{ hint }}
          </button>
        </div>
      </div>
    </div>

    <div class="w-full flex justify-end">
      <NextButton
        type="button"
        :label="t('CADENCE.TEMPLATES_SETTINGS.SAVE')"
        @click="save"
      />
    </div>
  </div>
</template>
