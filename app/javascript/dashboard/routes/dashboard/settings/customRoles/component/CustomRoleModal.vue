<script setup>
import { ref, reactive, computed, onMounted, watch } from 'vue';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required, minLength } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import {
  PERMISSION_MODULES,
  MANAGE_ALL_CONVERSATION_PERMISSIONS,
  CONVERSATION_UNASSIGNED_PERMISSIONS,
  CONVERSATION_PARTICIPATING_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  mode: {
    type: String,
    default: 'add',
    validator: value => ['add', 'edit'].includes(value),
  },
  selectedRole: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['close']);

const store = useStore();
const { t } = useI18n();

const name = ref('');
const description = ref('');
const selectedPermissions = ref([]);

const nameInput = ref(null);

const addCustomRole = reactive({
  showLoading: false,
  message: '',
});

const rules = computed(() => ({
  name: { required, minLength: minLength(2) },
  description: { required },
  selectedPermissions: { required, minLength: minLength(1) },
}));

const v$ = useVuelidate(rules, { name, description, selectedPermissions });

const resetForm = () => {
  name.value = '';
  description.value = '';
  selectedPermissions.value = [];
  v$.value.$reset();
};

const populateEditForm = () => {
  name.value = props.selectedRole.name || '';
  description.value = props.selectedRole.description || '';
  selectedPermissions.value = props.selectedRole.permissions || [];
};

watch(
  selectedPermissions,
  (newValue, oldValue) => {
    // Check if manage all conversation permission is added or removed
    const hasAddedManageAllConversation =
      newValue.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS) &&
      !oldValue.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS);
    const hasRemovedManageAllConversation =
      oldValue.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS) &&
      !newValue.includes(MANAGE_ALL_CONVERSATION_PERMISSIONS);

    if (hasAddedManageAllConversation) {
      // If manage all conversation permission is added,
      // then add unassigned and participating permissions automatically
      selectedPermissions.value = [
        ...new Set([
          ...selectedPermissions.value,
          CONVERSATION_UNASSIGNED_PERMISSIONS,
          CONVERSATION_PARTICIPATING_PERMISSIONS,
        ]),
      ];
    } else if (hasRemovedManageAllConversation) {
      // If manage all conversation permission is removed,
      // then only remove manage all conversation permission
      selectedPermissions.value = selectedPermissions.value.filter(
        p => p !== MANAGE_ALL_CONVERSATION_PERMISSIONS
      );
    }
  },
  { deep: true }
);

onMounted(() => {
  if (props.mode === 'edit') {
    populateEditForm();
  }
  // Focus the name input when mounted
  nameInput.value?.focus();
});

const getTranslationKey = base => {
  return props.mode === 'edit'
    ? `CUSTOM_ROLE.EDIT.${base}`
    : `CUSTOM_ROLE.ADD.${base}`;
};

const modalTitle = computed(() => t(getTranslationKey('TITLE')));
const modalDescription = computed(() => t(getTranslationKey('DESC')));
const submitButtonText = computed(() => t(getTranslationKey('SUBMIT')));

// Sin acceso / Solo ver / Administrar por módulo. "Administrar" implica "Ver".
const MODULE_LEVELS = { NONE: 'none', VIEW: 'view', MANAGE: 'manage' };

const moduleLevel = permissionModule => {
  if (selectedPermissions.value.includes(permissionModule.managePermission)) {
    return MODULE_LEVELS.MANAGE;
  }
  if (selectedPermissions.value.includes(permissionModule.viewPermission)) {
    return MODULE_LEVELS.VIEW;
  }
  return MODULE_LEVELS.NONE;
};

const setModuleLevel = (permissionModule, level) => {
  const withoutModule = selectedPermissions.value.filter(
    permission =>
      permission !== permissionModule.viewPermission &&
      permission !== permissionModule.managePermission
  );

  if (level === MODULE_LEVELS.VIEW) {
    withoutModule.push(permissionModule.viewPermission);
  } else if (level === MODULE_LEVELS.MANAGE) {
    withoutModule.push(permissionModule.managePermission);
  }

  selectedPermissions.value = withoutModule;
};

const handleCustomRole = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  addCustomRole.showLoading = true;
  try {
    const roleData = {
      name: name.value,
      description: description.value,
      permissions: selectedPermissions.value,
    };

    if (props.mode === 'edit') {
      await store.dispatch('customRole/updateCustomRole', {
        id: props.selectedRole.id,
        ...roleData,
      });
      useAlert(t('CUSTOM_ROLE.EDIT.API.SUCCESS_MESSAGE'));
    } else {
      await store.dispatch('customRole/createCustomRole', roleData);
      useAlert(t('CUSTOM_ROLE.ADD.API.SUCCESS_MESSAGE'));
    }

    resetForm();
    emit('close');
  } catch (error) {
    const errorMessage =
      error?.message || t(`CUSTOM_ROLE.FORM.API.ERROR_MESSAGE`);
    useAlert(errorMessage);
  } finally {
    addCustomRole.showLoading = false;
  }
};

const isSubmitDisabled = computed(
  () => v$.value.$invalid || addCustomRole.showLoading
);
</script>

<template>
  <div class="flex flex-col h-auto overflow-auto">
    <woot-modal-header
      :header-title="modalTitle"
      :header-content="modalDescription"
    />
    <form class="flex flex-col w-full" @submit.prevent="handleCustomRole">
      <div class="w-full">
        <label :class="{ error: v$.name.$error }">
          {{ $t('CUSTOM_ROLE.FORM.NAME.LABEL') }}
          <input
            ref="nameInput"
            v-model.trim="name"
            type="text"
            :placeholder="$t('CUSTOM_ROLE.FORM.NAME.PLACEHOLDER')"
            @blur="v$.name.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ error: v$.description.$error }">
          {{ $t('CUSTOM_ROLE.FORM.DESCRIPTION.LABEL') }}

          <textarea
            v-model="description"
            :rows="3"
            :placeholder="$t('CUSTOM_ROLE.FORM.DESCRIPTION.PLACEHOLDER')"
            @blur="v$.description.$touch"
          />
        </label>
      </div>

      <div class="w-full">
        <label :class="{ 'text-n-ruby-9': v$.selectedPermissions.$error }">
          {{ $t('CUSTOM_ROLE.FORM.PERMISSIONS.LABEL') }}
        </label>
        <div
          class="flex flex-col gap-3 mb-4 mt-2 border border-n-weak rounded-lg p-3"
        >
          <!-- Conversaciones conserva su jerarquía especial de 3 niveles -->
          <div class="flex flex-col gap-1.5 pb-3 border-b border-n-weak">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('CUSTOM_ROLE.PERMISSIONS.MODULE_LABELS.CONVERSATION') }}
            </span>
            <div class="flex items-center gap-4 flex-wrap">
              <label
                v-for="permission in [
                  'conversation_manage',
                  'conversation_unassigned_manage',
                  'conversation_participating_manage',
                ]"
                :key="permission"
                class="flex items-center gap-1.5 text-sm font-normal"
              >
                <input
                  v-model="selectedPermissions"
                  type="checkbox"
                  :value="permission"
                />
                {{ $t(`CUSTOM_ROLE.PERMISSIONS.${permission.toUpperCase()}`) }}
              </label>
            </div>
          </div>

          <!-- Matriz Sin acceso / Solo ver / Administrar para el resto de módulos -->
          <div
            v-for="permissionModule in PERMISSION_MODULES"
            :key="permissionModule.key"
            class="flex items-center justify-between flex-wrap gap-2"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{
                $t(
                  `CUSTOM_ROLE.PERMISSIONS.MODULE_LABELS.${permissionModule.key.toUpperCase()}`
                )
              }}
            </span>
            <div class="flex items-center gap-4">
              <label
                v-for="level in ['none', 'view', 'manage']"
                :key="level"
                class="flex items-center gap-1.5 text-sm font-normal"
              >
                <input
                  type="radio"
                  :name="`module-${permissionModule.key}`"
                  :checked="moduleLevel(permissionModule) === level"
                  @change="setModuleLevel(permissionModule, level)"
                />
                {{
                  $t(
                    `CUSTOM_ROLE.FORM.PERMISSIONS.LEVELS.${level.toUpperCase()}`
                  )
                }}
              </label>
            </div>
          </div>
        </div>
      </div>

      <div class="flex flex-row justify-end w-full gap-2 px-0 py-2">
        <Button
          faded
          slate
          type="reset"
          :label="$t('CUSTOM_ROLE.FORM.CANCEL_BUTTON_TEXT')"
          @click.prevent="emit('close')"
        />
        <Button
          type="submit"
          :label="submitButtonText"
          :disabled="isSubmitDisabled"
          :is-loading="addCustomRole.showLoading"
        />
      </div>
    </form>
  </div>
</template>
