<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import QuotesAPI from 'dashboard/api/quotes';
import QuoteDevelopmentRulesAPI from 'dashboard/api/quoteDevelopmentRules';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';

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
const isSaving = ref(false);
const error = ref(null);

// Cada tramo: { id, hasta_meses, msi, requires_authorization, markedForDestroy }. `hasta_meses`
// vacío significa "sin límite superior" — solo un tramo puede tener este valor. `markedForDestroy`
// se traduce a la llave `_destroy` que espera accepts_nested_attributes_for solo al armar el payload
// en save(), para no meter ese nombre en todo el resto del componente.
const emptyTier = () => ({
  id: null,
  hasta_meses: '',
  msi: false,
  requires_authorization: false,
  markedForDestroy: false,
});

const tiers = ref([emptyTier()]);

const desarrolloOptions = computed(() =>
  desarrollos.value.map(name => ({ value: name, label: name }))
);

const isEdit = computed(() => props.mode === 'edit');

const visibleTiers = computed(() =>
  tiers.value.filter(tier => !tier.markedForDestroy)
);

const openEndedCount = computed(
  () => visibleTiers.value.filter(tier => tier.hasta_meses === '').length
);

const isSubmitDisabled = computed(
  () =>
    !desarrollo.value ||
    !visibleTiers.value.length ||
    openEndedCount.value > 1 ||
    isSaving.value
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
    tiers.value = (props.selectedRule.quote_development_rule_tiers || []).map(
      tier => ({
        id: tier.id,
        hasta_meses: tier.hasta_meses ?? '',
        msi: tier.msi,
        requires_authorization: tier.requires_authorization,
        markedForDestroy: false,
      })
    );
    if (!tiers.value.length) tiers.value = [emptyTier()];
  }
});

const addTier = () => {
  tiers.value.push(emptyTier());
};

const removeTier = index => {
  const tier = tiers.value[index];
  if (tier.id) {
    tier.markedForDestroy = true;
  } else {
    tiers.value.splice(index, 1);
  }
};

const save = async () => {
  isSaving.value = true;
  error.value = null;
  try {
    const data = {
      desarrollo: desarrollo.value,
      quote_development_rule_tiers_attributes: tiers.value.map(tier =>
        // eslint-disable-next-line no-underscore-dangle -- llave requerida por
        // accepts_nested_attributes_for en el backend
        ({
          id: tier.id || undefined,
          hasta_meses:
            tier.hasta_meses === '' ? null : Number(tier.hasta_meses),
          msi: tier.msi,
          requires_authorization: tier.requires_authorization,
          _destroy: tier.markedForDestroy,
        })
      ),
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

      <div class="w-full">
        <div class="flex items-center justify-between mb-2">
          <label class="block text-sm font-medium text-n-slate-12">
            {{ t('QUOTE_DEVELOPMENT_RULES.FORM.TIERS.LABEL') }}
          </label>
          <Button
            type="button"
            size="xs"
            variant="ghost"
            icon="i-lucide-plus"
            :label="t('QUOTE_DEVELOPMENT_RULES.FORM.TIERS.ADD')"
            :disabled="isSaving"
            @click="addTier"
          />
        </div>

        <div class="flex flex-col gap-2">
          <template v-for="(tier, index) in tiers" :key="index">
            <div
              v-if="!tier.markedForDestroy"
              class="flex items-end gap-3 border border-n-weak rounded-lg p-3"
            >
              <div class="w-32 shrink-0">
                <Input
                  v-model="tier.hasta_meses"
                  type="number"
                  min="1"
                  :label="
                    t('QUOTE_DEVELOPMENT_RULES.FORM.TIERS.HASTA_MESES.LABEL')
                  "
                  :placeholder="
                    t(
                      'QUOTE_DEVELOPMENT_RULES.FORM.TIERS.HASTA_MESES.PLACEHOLDER'
                    )
                  "
                  :disabled="isSaving"
                />
              </div>
              <label
                class="flex items-center gap-2 text-sm text-n-slate-12 pb-2"
              >
                <Checkbox v-model="tier.msi" :disabled="isSaving" />
                {{ t('QUOTE_DEVELOPMENT_RULES.FORM.TIERS.MSI') }}
              </label>
              <label
                class="flex items-center gap-2 text-sm text-n-slate-12 pb-2"
              >
                <Checkbox
                  v-model="tier.requires_authorization"
                  :disabled="isSaving"
                />
                {{
                  t('QUOTE_DEVELOPMENT_RULES.FORM.TIERS.REQUIRES_AUTHORIZATION')
                }}
              </label>
              <Button
                type="button"
                size="xs"
                variant="ghost"
                color="ruby"
                icon="i-lucide-trash-2"
                class="ms-auto mb-2"
                :disabled="isSaving || visibleTiers.length <= 1"
                @click="removeTier(index)"
              />
            </div>
          </template>
        </div>

        <p v-if="openEndedCount > 1" class="text-n-ruby-11 text-xs mt-2">
          {{ t('QUOTE_DEVELOPMENT_RULES.FORM.TIERS.OPEN_ENDED_ERROR') }}
        </p>
        <p v-else class="text-n-slate-10 text-xs mt-2">
          {{ t('QUOTE_DEVELOPMENT_RULES.FORM.TIERS.HASTA_MESES.HINT') }}
        </p>
      </div>

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
