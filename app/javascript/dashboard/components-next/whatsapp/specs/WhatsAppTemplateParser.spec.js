import { mount, flushPromises } from '@vue/test-utils';
import { createStore } from 'vuex';
import WhatsAppTemplateParser from '../WhatsAppTemplateParser.vue';
import { getCadenceStepDefinitions } from 'dashboard/helper/cadenceStepDefaultsCache';

vi.mock('dashboard/helper/cadenceStepDefaultsCache', () => ({
  getCadenceStepDefinitions: vi.fn(),
}));

const mediaTemplate = {
  name: 'cadencia_primer_contacto',
  language: 'es_MX',
  category: 'MARKETING',
  components: [
    { type: 'HEADER', format: 'VIDEO' },
    { type: 'BODY', text: 'Hola' },
  ],
};

const buildStore = (inboxesById = {}) =>
  createStore({
    modules: {
      inboxes: {
        namespaced: true,
        getters: {
          getInbox: () => id => inboxesById[id] || {},
        },
      },
    },
  });

const mountParser = (props, inboxesById = {}) =>
  mount(WhatsAppTemplateParser, {
    props,
    global: { plugins: [buildStore(inboxesById)] },
  });

describe('WhatsAppTemplateParser.vue - cadence media prefill', () => {
  beforeEach(() => {
    getCadenceStepDefinitions.mockReset();
  });

  it('prefills media_url when a matching cadence step is configured for the inbox', async () => {
    getCadenceStepDefinitions.mockResolvedValue([
      {
        template_name: 'cadencia_primer_contacto',
        template_language: 'es_MX',
        media_url: 'https://cdn.example.com/v.mp4',
        media_type: 'video',
        media_name: null,
      },
    ]);

    const wrapper = mountParser({ template: mediaTemplate, inboxId: 7 });
    await flushPromises();

    expect(getCadenceStepDefinitions).toHaveBeenCalledWith(7);
    expect(wrapper.find('input[type="url"]').element.value).toBe(
      'https://cdn.example.com/v.mp4'
    );
  });

  it('leaves the field blank when there is no matching cadence step nor inbox default', async () => {
    getCadenceStepDefinitions.mockResolvedValue([]);

    const wrapper = mountParser({ template: mediaTemplate, inboxId: 7 });
    await flushPromises();

    expect(wrapper.find('input[type="url"]').element.value).toBe('');
  });

  it('does not look up cadence steps when no inboxId is provided', async () => {
    const wrapper = mountParser({ template: mediaTemplate });
    await flushPromises();

    expect(getCadenceStepDefinitions).not.toHaveBeenCalled();
    expect(wrapper.find('input[type="url"]').element.value).toBe('');
  });
});

describe('WhatsAppTemplateParser.vue - inbox-level template media default', () => {
  beforeEach(() => {
    getCadenceStepDefinitions.mockReset();
    getCadenceStepDefinitions.mockResolvedValue([]);
  });

  it('prefills media_url from the inbox default when there is no cadence step override', async () => {
    const wrapper = mountParser(
      { template: mediaTemplate, inboxId: 7 },
      {
        7: {
          template_inbox_media_defaults: {
            cadencia_primer_contacto: {
              media_url: 'https://cdn.example.com/global-default.mp4',
            },
          },
        },
      }
    );
    await flushPromises();

    expect(wrapper.find('input[type="url"]').element.value).toBe(
      'https://cdn.example.com/global-default.mp4'
    );
  });

  it('lets a cadence step media_url override the inbox default', async () => {
    getCadenceStepDefinitions.mockResolvedValue([
      {
        template_name: 'cadencia_primer_contacto',
        template_language: 'es_MX',
        media_url: 'https://cdn.example.com/cadence-specific.mp4',
        media_type: 'video',
        media_name: null,
      },
    ]);

    const wrapper = mountParser(
      { template: mediaTemplate, inboxId: 7 },
      {
        7: {
          template_inbox_media_defaults: {
            cadencia_primer_contacto: {
              media_url: 'https://cdn.example.com/global-default.mp4',
            },
          },
        },
      }
    );
    await flushPromises();

    expect(wrapper.find('input[type="url"]').element.value).toBe(
      'https://cdn.example.com/cadence-specific.mp4'
    );
  });
});
