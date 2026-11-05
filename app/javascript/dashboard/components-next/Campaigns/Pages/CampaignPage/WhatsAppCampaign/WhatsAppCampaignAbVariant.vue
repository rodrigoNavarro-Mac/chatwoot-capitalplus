<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';

// Optional second template for an A/B test: each recipient gets one of the two templates
// (Campaigns::TemplateVariantPicker), split by `ab_split` (% that gets template A).
const props = defineProps({
  inboxId: { type: Number, default: null },
  templateOptions: { type: Array, default: () => [] },
  primaryTemplateId: { type: [Number, String], default: null },
  selectedCampaign: { type: Object, default: null },
});

const { t } = useI18n();

const enabled = ref(false);
const templateId = ref(null);
const split = ref(50);
const parserRef = ref(null);

const options = computed(() =>
  props.templateOptions.filter(
    option => option.value !== props.primaryTemplateId
  )
);

const selectedTemplate = computed(
  () =>
    options.value.find(option => option.value === templateId.value)?.template
);

const splitIsValid = computed(
  () => Number.isInteger(split.value) && split.value >= 1 && split.value <= 99
);

const isInvalid = computed(() => {
  if (!enabled.value) return false;
  if (!selectedTemplate.value || !splitIsValid.value) return true;
  return parserRef.value?.isFormInvalid !== false;
});

watch(
  () => props.selectedCampaign,
  campaign => {
    enabled.value = !!campaign?.template_variant_b?.template_params?.name;
    split.value = campaign?.ab_split ?? 50;
  },
  { immediate: true }
);

// Same name-matching as template A once the inbox templates load
watch(options, list => {
  const name =
    props.selectedCampaign?.template_variant_b?.template_params?.name;
  if (!name || templateId.value) return;
  const match = list.find(option => option.template?.name === name);
  if (match) templateId.value = match.value;
});

watch(
  () => props.inboxId,
  (newVal, oldVal) => {
    if (oldVal !== null) templateId.value = null;
  }
);

const buildPayload = () => {
  if (!enabled.value || !selectedTemplate.value) {
    return { template_variant_b: null, ab_split: 50 };
  }
  const template = selectedTemplate.value;
  const parser = parserRef.value;
  return {
    template_variant_b: {
      message: parser?.renderedTemplate || '',
      template_params: {
        name: template.name || '',
        namespace: template.namespace || '',
        category: template.category || 'UTILITY',
        language: template.language || 'en_US',
        processed_params: parser?.processedParams || {},
      },
    },
    ab_split: split.value,
  };
};

defineExpose({ isInvalid, buildPayload });
</script>

<template>
  <div class="flex flex-col gap-3 p-3 border rounded-lg border-n-weak">
    <div class="flex items-center justify-between gap-3">
      <div class="flex flex-col">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AB_TEST.LABEL') }}
        </span>
        <span class="text-xs text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AB_TEST.HELP') }}
        </span>
      </div>
      <Switch v-model="enabled" />
    </div>

    <template v-if="enabled">
      <div class="flex flex-col gap-1">
        <label
          for="template-b"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ t('CAMPAIGN.WHATSAPP.CREATE.FORM.AB_TEST.TEMPLATE_B') }}
        </label>
        <ComboBox
          id="template-b"
          v-model="templateId"
          :options="options"
          :placeholder="t('CAMPAIGN.WHATSAPP.CREATE.FORM.TEMPLATE.PLACEHOLDER')"
          class="[&>div>button]:bg-n-alpha-black2"
        />
      </div>

      <WhatsAppTemplateParser
        v-if="selectedTemplate"
        ref="parserRef"
        :template="selectedTemplate"
        :inbox-id="inboxId"
        autofill-name-variable
      />

      <Input
        v-model.number="split"
        type="number"
        min="1"
        max="99"
        :label="t('CAMPAIGN.WHATSAPP.CREATE.FORM.AB_TEST.SPLIT.LABEL')"
        :message="
          splitIsValid
            ? t('CAMPAIGN.WHATSAPP.CREATE.FORM.AB_TEST.SPLIT.HELP', {
                a: split,
                b: 100 - split,
              })
            : t('CAMPAIGN.WHATSAPP.CREATE.FORM.AB_TEST.SPLIT.ERROR')
        "
        :message-type="splitIsValid ? 'info' : 'error'"
      />
    </template>
  </div>
</template>
