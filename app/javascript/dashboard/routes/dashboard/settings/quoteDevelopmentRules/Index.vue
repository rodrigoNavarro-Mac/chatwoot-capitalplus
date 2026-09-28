<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import QuoteDevelopmentRulesAPI from 'dashboard/api/quoteDevelopmentRules';
import SettingsLayout from '../SettingsLayout.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import QuoteDevelopmentRuleModal from './component/QuoteDevelopmentRuleModal.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { BaseTable } from 'dashboard/components-next/table';

const { t } = useI18n();

const records = ref([]);
const isFetching = ref(false);
const showModal = ref(false);
const modalMode = ref('add');
const selectedRule = ref(null);
const showDeleteConfirmationPopup = ref(false);
const activeRule = ref({});
const deleting = ref({});

const tableHeaders = computed(() => [
  t('QUOTE_DEVELOPMENT_RULES.LIST.TABLE_HEADER.DESARROLLO'),
  t('QUOTE_DEVELOPMENT_RULES.LIST.TABLE_HEADER.TIERS'),
  t('QUOTE_DEVELOPMENT_RULES.LIST.TABLE_HEADER.ACTIONS'),
]);

const deleteMessage = computed(() => ` ${activeRule.value.desarrollo} ? `);

// Los tramos ya llegan ordenados por hasta_meses ascendente (nulls al final) desde el backend —
// solo hace falta llevar el límite anterior para armar el rango "13–24" de cada tramo.
const tierRanges = rule => {
  let previousMax = 0;
  return (rule.quote_development_rule_tiers || []).map(tier => {
    const from = previousMax + 1;
    const range =
      tier.hasta_meses === null
        ? t('QUOTE_DEVELOPMENT_RULES.LIST.TIER_RANGE.OPEN_ENDED', { from })
        : t('QUOTE_DEVELOPMENT_RULES.LIST.TIER_RANGE.BOUNDED', {
            from,
            to: tier.hasta_meses,
          });
    previousMax = tier.hasta_meses;
    return { ...tier, range };
  });
};

const fetchRules = async () => {
  isFetching.value = true;
  try {
    const response = await QuoteDevelopmentRulesAPI.get();
    records.value = response.data;
  } catch (error) {
    // Ignore Error
  } finally {
    isFetching.value = false;
  }
};

onMounted(() => {
  fetchRules();
});

const openAddModal = () => {
  modalMode.value = 'add';
  selectedRule.value = null;
  showModal.value = true;
};

const openEditModal = rule => {
  modalMode.value = 'edit';
  selectedRule.value = rule;
  showModal.value = true;
};

const hideModal = () => {
  selectedRule.value = null;
  showModal.value = false;
};

const openDeletePopup = rule => {
  activeRule.value = rule;
  showDeleteConfirmationPopup.value = true;
};

const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const confirmDeletion = async () => {
  closeDeletePopup();
  deleting.value[activeRule.value.id] = true;
  try {
    await QuoteDevelopmentRulesAPI.delete(activeRule.value.id);
    useAlert(t('QUOTE_DEVELOPMENT_RULES.DELETE.API.SUCCESS_MESSAGE'));
    await fetchRules();
  } catch (error) {
    useAlert(t('QUOTE_DEVELOPMENT_RULES.DELETE.API.ERROR_MESSAGE'));
  } finally {
    deleting.value[activeRule.value.id] = false;
    activeRule.value = {};
  }
};
</script>

<template>
  <SettingsLayout
    :is-loading="isFetching"
    :loading-message="t('QUOTE_DEVELOPMENT_RULES.LOADING')"
    :no-records-found="!isFetching && !records.length"
    :no-records-message="t('QUOTE_DEVELOPMENT_RULES.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        :title="t('QUOTE_DEVELOPMENT_RULES.HEADER')"
        :description="t('QUOTE_DEVELOPMENT_RULES.DESCRIPTION')"
      >
        <template v-if="records.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ t('QUOTE_DEVELOPMENT_RULES.COUNT', { n: records.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="t('QUOTE_DEVELOPMENT_RULES.HEADER_BTN_TXT')"
            size="sm"
            @click="openAddModal"
          />
        </template>
      </BaseSettingsHeader>
    </template>

    <template #body>
      <BaseTable
        :headers="tableHeaders"
        :items="records"
        :no-data-message="t('QUOTE_DEVELOPMENT_RULES.LIST.404')"
      >
        <template #row="{ items }">
          <tr
            v-for="rule in items"
            :key="rule.id"
            class="border-b border-n-weak"
          >
            <td class="py-2 px-4 text-n-slate-12 align-top">
              {{ rule.desarrollo }}
            </td>
            <td class="py-2 px-4 text-n-slate-12">
              <ul class="flex flex-col gap-1">
                <li
                  v-for="tier in tierRanges(rule)"
                  :key="tier.id"
                  class="flex items-center gap-2 text-xs"
                >
                  <span class="font-medium text-n-slate-12 w-16 shrink-0">
                    {{ tier.range }}
                  </span>
                  <span
                    v-if="tier.msi"
                    class="px-1.5 py-0.5 rounded-full bg-n-teal-3 text-n-teal-11"
                  >
                    {{ t('QUOTE_DEVELOPMENT_RULES.FORM.TIERS.MSI') }}
                  </span>
                  <span
                    v-if="tier.requires_authorization"
                    class="px-1.5 py-0.5 rounded-full bg-n-amber-3 text-n-amber-11"
                  >
                    {{
                      t(
                        'QUOTE_DEVELOPMENT_RULES.FORM.TIERS.REQUIRES_AUTHORIZATION'
                      )
                    }}
                  </span>
                </li>
              </ul>
            </td>
            <td class="py-2 px-4 align-top">
              <div class="flex gap-2">
                <Button
                  icon="i-lucide-pen"
                  variant="ghost"
                  size="sm"
                  color="slate"
                  @click="openEditModal(rule)"
                />
                <Button
                  icon="i-lucide-trash-2"
                  variant="ghost"
                  size="sm"
                  color="ruby"
                  :is-loading="deleting[rule.id]"
                  @click="openDeletePopup(rule)"
                />
              </div>
            </td>
          </tr>
        </template>
      </BaseTable>
    </template>

    <woot-modal v-model:show="showModal" :on-close="hideModal">
      <QuoteDevelopmentRuleModal
        :mode="modalMode"
        :selected-rule="selectedRule"
        @close="hideModal"
        @saved="fetchRules"
      />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="t('QUOTE_DEVELOPMENT_RULES.DELETE.CONFIRM.TITLE')"
      :message="t('QUOTE_DEVELOPMENT_RULES.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="t('QUOTE_DEVELOPMENT_RULES.DELETE.CONFIRM.YES')"
      :reject-text="t('QUOTE_DEVELOPMENT_RULES.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>
