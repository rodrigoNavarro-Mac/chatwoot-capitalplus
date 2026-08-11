<script setup>
import { ref, computed, toRef } from 'vue';
import { useAlert } from 'dashboard/composables';
import {
  useFunctionGetter,
  useMapGetter,
  useStore,
} from 'dashboard/composables/store';
import {
  COMPONENT_TYPES,
  MEDIA_FORMATS,
  findComponentByType,
} from 'dashboard/helper/templateHelper';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  inboxId: {
    type: Number,
    default: undefined,
  },
});

const emit = defineEmits(['onSelect']);

const { t } = useI18n();
const store = useStore();
const query = ref('');
const isRefreshing = ref(false);

const HEADER_ICONS = {
  IMAGE: 'i-lucide-image',
  VIDEO: 'i-lucide-video',
  DOCUMENT: 'i-lucide-file-text',
};

const BUTTON_ICONS = {
  QUICK_REPLY: 'i-lucide-corner-up-left',
  URL: 'i-lucide-external-link',
  PHONE_NUMBER: 'i-lucide-phone',
  COPY_CODE: 'i-lucide-copy',
};

const whatsAppTemplateMessages = useFunctionGetter(
  'inboxes/getFilteredWhatsAppTemplates',
  toRef(props, 'inboxId')
);

const getInbox = useMapGetter('inboxes/getInbox');
const mediaDefaults = computed(
  () => getInbox.value(props.inboxId)?.template_inbox_media_defaults || {}
);

const filteredTemplateMessages = computed(() =>
  whatsAppTemplateMessages.value.filter(template =>
    template.name.toLowerCase().includes(query.value.toLowerCase())
  )
);

const getTemplateBody = template => {
  return findComponentByType(template, COMPONENT_TYPES.BODY)?.text || '';
};

const getTemplateHeader = template => {
  return findComponentByType(template, COMPONENT_TYPES.HEADER);
};

const getTemplateFooter = template => {
  return findComponentByType(template, COMPONENT_TYPES.FOOTER);
};

const getTemplateButtons = template => {
  return findComponentByType(template, COMPONENT_TYPES.BUTTONS);
};

const hasMediaContent = template => {
  const header = getTemplateHeader(template);
  return header && MEDIA_FORMATS.includes(header.format);
};

const getMediaDefault = template => mediaDefaults.value[template.name];

const getHeaderThumbnail = template => {
  const header = getTemplateHeader(template);
  if (header?.format !== 'IMAGE') return '';
  return getMediaDefault(template)?.media_url || '';
};

const getHeaderIcon = template => {
  const format = getTemplateHeader(template)?.format;
  return HEADER_ICONS[format] || 'i-lucide-file';
};

const formatLabel = format => {
  if (!format) return '';
  return format.charAt(0) + format.slice(1).toLowerCase();
};

const getButtonIcon = button => BUTTON_ICONS[button.type] || 'i-lucide-square';

const getButtonSubtitle = button => {
  if (button.type === 'URL' && button.url) {
    try {
      return new URL(button.url).hostname;
    } catch (error) {
      return button.url;
    }
  }
  if (button.type === 'PHONE_NUMBER' && button.phone_number) {
    return button.phone_number;
  }
  return '';
};

const refreshTemplates = async () => {
  isRefreshing.value = true;
  try {
    await store.dispatch('inboxes/syncTemplates', props.inboxId);
    useAlert(t('WHATSAPP_TEMPLATES.PICKER.REFRESH_SUCCESS'));
  } catch (error) {
    useAlert(t('WHATSAPP_TEMPLATES.PICKER.REFRESH_ERROR'));
  } finally {
    isRefreshing.value = false;
  }
};
</script>

<template>
  <div class="w-full">
    <div class="flex gap-2 mb-2.5">
      <div
        class="flex flex-1 gap-1 items-center px-2.5 py-0 rounded-lg bg-n-alpha-black2 outline outline-1 outline-n-weak hover:outline-n-slate-6 dark:hover:outline-n-slate-6 focus-within:outline-n-brand dark:focus-within:outline-n-brand"
      >
        <fluent-icon icon="search" class="text-n-slate-12" size="16" />
        <input
          v-model="query"
          type="search"
          :placeholder="t('WHATSAPP_TEMPLATES.PICKER.SEARCH_PLACEHOLDER')"
          class="reset-base w-full h-9 bg-transparent text-n-slate-12 !text-sm !outline-0"
        />
      </div>
      <button
        :disabled="isRefreshing"
        class="flex justify-center items-center w-9 h-9 rounded-lg bg-n-alpha-black2 outline outline-1 outline-n-weak hover:outline-n-slate-6 dark:hover:outline-n-slate-6 hover:bg-n-alpha-2 dark:hover:bg-n-solid-2 disabled:opacity-50 disabled:cursor-not-allowed"
        :title="t('WHATSAPP_TEMPLATES.PICKER.REFRESH_BUTTON')"
        @click="refreshTemplates"
      >
        <Icon
          icon="i-lucide-refresh-ccw"
          class="text-n-slate-12 size-4"
          :class="{ 'animate-spin': isRefreshing }"
        />
      </button>
    </div>
    <div
      class="bg-n-background outline-n-container outline outline-1 rounded-lg max-h-[26rem] overflow-y-auto p-2.5 space-y-2"
    >
      <button
        v-for="template in filteredTemplateMessages"
        :key="`${template.name}-${template.language}`"
        class="flex flex-col gap-2 p-3 w-full text-left rounded-xl outline outline-1 outline-n-container hover:outline-n-brand hover:bg-n-alpha-1 dark:hover:bg-n-solid-2 transition-colors cursor-pointer"
        @click="emit('onSelect', template)"
      >
        <div class="flex justify-between items-start gap-2">
          <p class="text-sm font-medium text-n-slate-12 truncate">
            {{ template.name }}
          </p>
          <div class="flex gap-1 flex-shrink-0">
            <span
              class="inline-block px-2 py-0.5 text-xs leading-normal rounded-full bg-n-slate-3 text-n-slate-11"
            >
              {{ template.language }}
            </span>
            <span
              v-if="template.category"
              class="inline-block px-2 py-0.5 text-xs leading-normal rounded-full bg-n-slate-3 text-n-slate-11"
            >
              {{ template.category }}
            </span>
          </div>
        </div>

        <!-- Header -->
        <div v-if="getTemplateHeader(template)">
          <div
            v-if="getTemplateHeader(template).format === 'TEXT'"
            class="text-sm font-semibold text-n-slate-12"
          >
            {{ getTemplateHeader(template).text }}
          </div>
          <div
            v-else-if="hasMediaContent(template)"
            class="flex items-center gap-2 p-1.5 rounded-md bg-n-alpha-1"
          >
            <img
              v-if="getHeaderThumbnail(template)"
              :src="getHeaderThumbnail(template)"
              class="size-8 rounded object-cover flex-shrink-0"
            />
            <Icon
              v-else
              :icon="getHeaderIcon(template)"
              class="size-4 text-n-slate-11 flex-shrink-0"
            />
            <span class="text-xs text-n-slate-11">
              {{ formatLabel(getTemplateHeader(template).format) }}
              <template v-if="getMediaDefault(template)?.media_url">
                {{ t('WHATSAPP_TEMPLATES.PICKER.MEDIA_CONFIGURED') }}
              </template>
            </span>
          </div>
        </div>

        <!-- Body -->
        <p class="text-sm text-n-slate-12 whitespace-pre-line line-clamp-3">
          {{ getTemplateBody(template) }}
        </p>

        <!-- Footer -->
        <p
          v-if="getTemplateFooter(template)"
          class="text-xs text-n-slate-10 italic"
        >
          {{ getTemplateFooter(template).text }}
        </p>

        <!-- Buttons -->
        <div
          v-if="getTemplateButtons(template)"
          class="rounded-lg outline outline-1 outline-n-container divide-y divide-n-container overflow-hidden"
        >
          <div
            v-for="button in getTemplateButtons(template).buttons"
            :key="button.text"
            class="flex items-center gap-2 px-3 py-1.5 text-n-blue-11"
          >
            <Icon
              :icon="getButtonIcon(button)"
              class="size-3.5 flex-shrink-0"
            />
            <span class="text-sm font-medium truncate">{{ button.text }}</span>
            <span
              v-if="getButtonSubtitle(button)"
              class="ml-auto text-xs text-n-slate-10 truncate"
            >
              {{ getButtonSubtitle(button) }}
            </span>
          </div>
        </div>
      </button>
      <div v-if="!filteredTemplateMessages.length" class="py-8 text-center">
        <div v-if="query && whatsAppTemplateMessages.length">
          <p>
            {{ t('WHATSAPP_TEMPLATES.PICKER.NO_TEMPLATES_FOUND') }}
            <strong>{{ query }}</strong>
          </p>
        </div>
        <div v-else-if="!whatsAppTemplateMessages.length" class="space-y-4">
          <p class="text-n-slate-11">
            {{ t('WHATSAPP_TEMPLATES.PICKER.NO_TEMPLATES_AVAILABLE') }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
