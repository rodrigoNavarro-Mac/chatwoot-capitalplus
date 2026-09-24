<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { usePolicy } from 'dashboard/composables/usePolicy';
import { QUOTE_SENSITIVE_FIELDS_PERMISSION } from 'dashboard/constants/permissions.js';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  modelValue: { type: Object, required: true },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const { checkPermissions } = usePolicy();

// Solo UX: el backend (Api::V1::Accounts::QuotesController) es quien realmente bloquea estos tres
// campos para quien no tenga el permiso — aquí solo evitamos que parezcan editables.
const canEditSensitiveFields = computed(() =>
  checkPermissions(['administrator', QUOTE_SENSITIVE_FIELDS_PERMISSION])
);
const sensitiveFieldDisabled = computed(
  () => props.disabled || !canEditSensitiveFields.value
);

const update = (key, value) => {
  emit('update:modelValue', { ...props.modelValue, [key]: value });
};
</script>

<template>
  <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
    <Input
      :model-value="modelValue.nombre"
      :disabled="disabled"
      :label="t('QUOTES.FORM.NOMBRE')"
      @update:model-value="v => update('nombre', v)"
    />
    <Input
      :model-value="modelValue.lote"
      :disabled="disabled"
      :label="t('QUOTES.FORM.LOTE')"
      @update:model-value="v => update('lote', v)"
    />
    <Input
      :model-value="modelValue.desarrollo"
      :disabled="disabled"
      :label="t('QUOTES.FORM.DESARROLLO')"
      @update:model-value="v => update('desarrollo', v)"
    />
    <Input
      :model-value="modelValue.color"
      :disabled="disabled"
      :label="t('QUOTES.FORM.COLOR')"
      @update:model-value="v => update('color', v)"
    />
    <Input
      :model-value="modelValue.superficie"
      type="number"
      min="0"
      :disabled="disabled"
      :label="t('QUOTES.FORM.SUPERFICIE')"
      @update:model-value="v => update('superficie', v)"
    />
    <Input
      :model-value="modelValue.precio_m2"
      type="number"
      min="0"
      :disabled="disabled"
      :label="t('QUOTES.FORM.PRECIO_M2')"
      @update:model-value="v => update('precio_m2', v)"
    />
    <Input
      :model-value="modelValue.plazos"
      type="number"
      min="0"
      :disabled="disabled"
      :label="t('QUOTES.FORM.PLAZOS')"
      @update:model-value="v => update('plazos', v)"
    />
    <Input
      :model-value="modelValue.enganche"
      type="number"
      min="0"
      :disabled="disabled"
      :label="t('QUOTES.FORM.ENGANCHE')"
      @update:model-value="v => update('enganche', v)"
    />
    <Input
      :model-value="modelValue.interes"
      type="number"
      min="0"
      :disabled="sensitiveFieldDisabled"
      :label="t('QUOTES.FORM.INTERES')"
      :message="
        !canEditSensitiveFields ? t('QUOTES.FORM.SENSITIVE_FIELD_LOCKED') : ''
      "
      @update:model-value="v => update('interes', v)"
    />
    <Input
      :model-value="modelValue.meses_sin_intereses"
      type="number"
      min="0"
      :disabled="sensitiveFieldDisabled"
      :label="t('QUOTES.FORM.MSI')"
      :message="
        !canEditSensitiveFields ? t('QUOTES.FORM.SENSITIVE_FIELD_LOCKED') : ''
      "
      @update:model-value="v => update('meses_sin_intereses', v)"
    />
    <Input
      :model-value="modelValue.descuento"
      type="number"
      min="0"
      :disabled="sensitiveFieldDisabled"
      :label="t('QUOTES.FORM.DESCUENTO')"
      :message="
        !canEditSensitiveFields ? t('QUOTES.FORM.SENSITIVE_FIELD_LOCKED') : ''
      "
      @update:model-value="v => update('descuento', v)"
    />
    <Input
      :model-value="modelValue.fecha_entrega"
      type="date"
      :disabled="disabled"
      :label="t('QUOTES.FORM.FECHA_ENTREGA')"
      @update:model-value="v => update('fecha_entrega', v)"
    />
  </div>
</template>
