<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { getLanguageName } from 'dashboard/components/widgets/conversation/advancedFilterItems/languages';
import ContactDetailsItem from './ContactDetailsItem.vue';
import CustomAttributes from './customAttributes/CustomAttributes.vue';

const props = defineProps({
  conversationAttributes: {
    type: Object,
    default: () => ({}),
  },
  contactAttributes: {
    type: Object,
    default: () => ({}),
  },
  conversationTimings: {
    type: Object,
    default: () => ({}),
  },
});

const { t } = useI18n();

const referer = computed(() => props.conversationAttributes.referer);
const initiatedAt = computed(
  () => props.conversationAttributes.initiated_at?.timestamp
);

const browserInfo = computed(() => props.conversationAttributes.browser);

const browserName = computed(() => {
  if (!browserInfo.value) return '';
  const { browser_name: name = '', browser_version: version = '' } =
    browserInfo.value;
  return `${name} ${version}`;
});

const browserLanguage = computed(() =>
  getLanguageName(props.conversationAttributes.browser_language)
);

const platformName = computed(() => {
  if (!browserInfo.value) return '';
  const { platform_name: name = '', platform_version: version = '' } =
    browserInfo.value;
  return `${name} ${version}`;
});

const createdAtIp = computed(() => props.contactAttributes.created_at_ip);

const firstResponseTime = computed(() => {
  const { first_reply_created_at, created_at } = props.conversationTimings;
  if (!first_reply_created_at || !created_at) return null;
  const totalSeconds = first_reply_created_at - created_at;
  if (totalSeconds <= 0) return null;
  if (totalSeconds < 60)
    return t('CONTACT_PANEL.FIRST_RESPONSE_TIME_SECONDS', { n: totalSeconds });
  const minutes = Math.floor(totalSeconds / 60);
  if (minutes < 60)
    return t('CONTACT_PANEL.FIRST_RESPONSE_TIME_MINUTES', { n: minutes });
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  if (remainingMinutes === 0)
    return t('CONTACT_PANEL.FIRST_RESPONSE_TIME_HOURS', { n: hours });
  return t('CONTACT_PANEL.FIRST_RESPONSE_TIME_HOURS_MINUTES', {
    hours,
    minutes: remainingMinutes,
  });
});

const staticElements = computed(() =>
  [
    {
      content: initiatedAt,
      title: 'CONTACT_PANEL.INITIATED_AT',
      key: 'static-initiated-at',
      type: 'static_attribute',
    },
    {
      content: browserLanguage,
      title: 'CONTACT_PANEL.BROWSER_LANGUAGE',
      key: 'static-browser-language',
      type: 'static_attribute',
    },
    {
      content: referer,
      title: 'CONTACT_PANEL.INITIATED_FROM',
      key: 'static-referer',
      type: 'static_attribute',
    },
    {
      content: browserName,
      title: 'CONTACT_PANEL.BROWSER',
      key: 'static-browser',
      type: 'static_attribute',
    },
    {
      content: platformName,
      title: 'CONTACT_PANEL.OS',
      key: 'static-platform',
      type: 'static_attribute',
    },
    {
      content: createdAtIp,
      title: 'CONTACT_PANEL.IP_ADDRESS',
      key: 'static-ip-address',
      type: 'static_attribute',
    },
    {
      content: firstResponseTime,
      title: 'CONTACT_PANEL.FIRST_RESPONSE_TIME',
      key: 'static-first-response-time',
      type: 'static_attribute',
    },
  ].filter(attribute => !!attribute.content.value)
);
</script>

<template>
  <div class="conversation--details">
    <CustomAttributes
      :static-elements="staticElements"
      attribute-class="conversation--attribute"
      attribute-from="conversation_panel"
      attribute-type="conversation_attribute"
    >
      <template #staticItem="{ element }">
        <ContactDetailsItem
          :key="element.title"
          :title="$t(element.title)"
          :value="element.content.value"
        >
          <a
            v-if="element.key === 'static-referer'"
            :href="element.content.value"
            rel="noopener noreferrer nofollow"
            target="_blank"
            class="text-n-brand"
          >
            {{ element.content.value }}
          </a>
        </ContactDetailsItem>
      </template>
    </CustomAttributes>
  </div>
</template>
