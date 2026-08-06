<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import WeeklyOpsReportsAPI from 'dashboard/api/weeklyOpsReports';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  inboxId: {
    type: [String, Number],
    required: true,
  },
});

const { t } = useI18n();

const isOpen = ref(false);
const isSaving = ref(false);
const accentColor = ref('#1f77b4');
const logoUrl = ref('');
const logoFile = ref(null);
const letterheadTemplateFilename = ref('');
const letterheadTemplateFile = ref(null);

const fetchBranding = async () => {
  if (!props.inboxId) return;

  try {
    const response = await WeeklyOpsReportsAPI.getBranding(props.inboxId);
    accentColor.value = response.data.accent_color_or_default;
    logoUrl.value = response.data.logo_url;
    letterheadTemplateFilename.value =
      response.data.letterhead_template_filename;
  } catch (error) {
    // No branding configured yet — keep the defaults.
  }
};

watch(() => props.inboxId, fetchBranding, { immediate: true });

const onLogoChange = event => {
  logoFile.value = event.target.files?.[0] || null;
};

const onLetterheadTemplateChange = event => {
  letterheadTemplateFile.value = event.target.files?.[0] || null;
};

const save = async () => {
  isSaving.value = true;
  try {
    const formData = new FormData();
    formData.append('accent_color', accentColor.value);
    if (logoFile.value) formData.append('logo', logoFile.value);
    if (letterheadTemplateFile.value) {
      formData.append('letterhead_template', letterheadTemplateFile.value);
    }

    const response = await WeeklyOpsReportsAPI.updateBranding(
      props.inboxId,
      formData
    );
    logoUrl.value = response.data.logo_url;
    logoFile.value = null;
    letterheadTemplateFilename.value =
      response.data.letterhead_template_filename;
    letterheadTemplateFile.value = null;
    useAlert(t('WEEKLY_OPS_REPORTS.BRANDING.SAVED'));
  } catch (error) {
    useAlert(t('WEEKLY_OPS_REPORTS.BRANDING.ERROR'));
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="mb-6">
    <button
      class="text-xs text-n-slate-11 hover:text-n-slate-12 underline"
      @click="isOpen = !isOpen"
    >
      {{ t('WEEKLY_OPS_REPORTS.BRANDING.TOGGLE') }}
    </button>

    <div
      v-if="isOpen"
      class="flex flex-wrap items-end gap-4 mt-3 p-4 rounded-xl shadow outline-1 outline outline-n-container bg-n-solid-2"
    >
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">
          {{ t('WEEKLY_OPS_REPORTS.BRANDING.ACCENT_COLOR') }}
        </label>
        <input v-model="accentColor" type="color" class="!mb-0 !h-8 w-16" />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">
          {{ t('WEEKLY_OPS_REPORTS.BRANDING.LOGO') }}
        </label>
        <img
          v-if="logoUrl"
          :src="logoUrl"
          class="h-8 object-contain mb-1"
          alt=""
        />
        <input
          type="file"
          accept="image/png,image/jpeg,image/webp"
          class="!mb-0 text-xs"
          @change="onLogoChange"
        />
      </div>
      <div class="flex flex-col gap-1">
        <label class="text-xs text-n-slate-11">
          {{ t('WEEKLY_OPS_REPORTS.BRANDING.LETTERHEAD_TEMPLATE') }}
        </label>
        <span
          v-if="letterheadTemplateFilename"
          class="text-xs text-n-slate-12 mb-1"
        >
          {{ letterheadTemplateFilename }}
        </span>
        <input
          type="file"
          accept=".docx"
          class="!mb-0 text-xs"
          @change="onLetterheadTemplateChange"
        />
      </div>
      <Button
        size="sm"
        :is-loading="isSaving"
        :label="t('WEEKLY_OPS_REPORTS.BRANDING.SAVE')"
        @click="save"
      />
    </div>
  </div>
</template>
