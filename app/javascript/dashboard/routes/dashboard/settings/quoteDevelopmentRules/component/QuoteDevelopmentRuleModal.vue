<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import QuotesAPI from 'dashboard/api/quotes';
import QuoteDevelopmentRulesAPI from 'dashboard/api/quoteDevelopmentRules';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  mode: {
    type: String,
    default: 'add',
    validator: value => ['add', 'edit'].includes(value),
  },
  selectedRule: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['close', 'saved']);

const { t } = useI18n();

const desarrollos = ref([]);
const desarrollo = ref('');
const msiAutoMaxPlazo = ref('');
const isSaving = ref(false);
const error = ref(null);

const desarrolloOptions = computed(() =>
  desarrollos.value.map(name => ({ value: name, label: name }))
);

const isEdit = computed(() => props.mode === 'edit');
const isSubmitDisabled = computed(
  () => !desarrollo.value || !msiAutoMaxPlazo.value || isSaving.value
);

const fetchDesarrollos = async () => {
  try {
    const response = await QuotesAPI.getDevelopments();
    desarrollos.value = response.data;
  } catch (e) {
    desarrollos.value = [];
  }
};

onMounted(() => {
  fetchDesarrollos();
  if (isEdit.value) {
    desarrollo.value = props.selectedRule.desarrollo;
    msiAutoMaxPlazo.value = props.selectedRule.msi_auto_max_plazo;
  }
});

const save = async () => {
  isSaving.value = true;
  error.value = null;
  try {
    const data = {
      desarrollo: desarrollo.value,
      msi_auto_max_plazo: msiAutoMaxPlazo.value,
    };
    if (isEdit.value) {
      await QuoteDevelopmentRulesAPI.update(props.selectedRule.id, data);
    } else {
      await QuoteDevelopmentRulesAPI.create(data);
    }
    useAlert(t('QUOTE_DEVELOPMENT_RULES.FORM.API.SUCCESS_MESSAGE'));
    emit('saved');
    emit('close');
  } catch (e) {
    error.value =
      e.response?.data?.error ||
      t('QUOTE_DEVELOPMENT_RULES.FORM.API.ERROR_MESSAGE');
  } finally {
    isSaving.value = false;
  }
};
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="
        isEdit
          ? t('QUOTE_DEVELOPMENT_RULES.EDIT.TITLE')
          : t('QUOTE_DEVELOPMENT_RULES.ADD.TITLE')
      "
      :header-content="t('QUOTE_DEVELOPMENT_RULES.FORM.DESC')"
    />
    <form class="flex flex-col w-full gap-4 px-0 py-2" @submit.prevent="save">
      <div class="w-full">
        <label class="mb-1 block text-sm font-medium text-n-slate-12">
          {{ t('QUOTE_DEVELOPMENT_RULES.FORM.DESARROLLO.LABEL') }}
        </label>
        <Select
          v-model="desarrollo"
          class="w-full"
          :options="desarrolloOptions"
          :placeholder="
            t('QUOTE_DEVELOPMENT_RULES.FORM.DESARROLLO.PLACEHOLDER')
          "
          :disabled="isEdit || isSaving"
        />
      </div>

      <Input
        v-model="msiAutoMaxPlazo"
        type="number"
        min="0"
        :label="t('QUOTE_DEVELOPMENT_RULES.FORM.MSI_AUTO_MAX_PLAZO.LABEL')"
        :placeholder="
          t('QUOTE_DEVELOPMENT_RULES.FORM.MSI_AUTO_MAX_PLAZO.PLACEHOLDER')
        "
        :disabled="isSaving"
      />

      <p v-if="error" class="text-n-ruby-11 text-xs">{{ error }}</p>

      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <Button
          variant="ghost"
          type="button"
          :label="t('QUOTE_DEVELOPMENT_RULES.FORM.CANCEL_BUTTON_TEXT')"
          @click="emit('close')"
        />
        <Button
          type="submit"
          :label="t('QUOTE_DEVELOPMENT_RULES.FORM.SUBMIT')"
          :disabled="isSubmitDisabled"
          :is-loading="isSaving"
        />
      </div>
    </form>
  </div>
</template>
